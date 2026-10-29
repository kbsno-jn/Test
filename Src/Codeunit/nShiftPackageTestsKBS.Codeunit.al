namespace Knowit.nShift.Test;

using Knowit.nShift;

codeunit 73963 "nShift Package Tests KBS"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "nShift Library Assert KBS";

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure VolumeIsCalculatedFromDimensions()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        Package: Record "nShift Package KBS";
    begin
        CreateShipment(ShipmentHeader);
        InitPackage(Package, ShipmentHeader, 10000);
        Package.Validate("Length (cm)", 60);
        Package.Validate("Width (cm)", 40);
        Package.Validate("Height (cm)", 40);
        Assert.AreEqual(0.096, Package."Volume (m3)", '60 × 40 × 40 cm skal gi 0,096 m³.');
        Assert.IsFalse(Package."Volume Overridden", 'Beregnet volum er ikke overstyrt.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure OverriddenVolumeIsKeptUntilReset()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        Package: Record "nShift Package KBS";
    begin
        CreateShipment(ShipmentHeader);
        InitPackage(Package, ShipmentHeader, 10000);
        Package.Validate("Length (cm)", 60);
        Package.Validate("Width (cm)", 40);
        Package.Validate("Height (cm)", 40);
        Package.Validate("Volume (m3)", 0.5);
        Package.Validate("Length (cm)", 100);
        Assert.AreEqual(0.5, Package."Volume (m3)", 'Overstyrt volum skal ikke endres når målene endres.');
        Assert.IsTrue(Package."Volume Overridden", 'Volumet skal være merket som overstyrt.');

        Package.Validate("Volume (m3)", 0);
        Assert.AreEqual(0.16, Package."Volume (m3)", 'Volum 0 skal beregne volumet på nytt fra målene.');
        Assert.IsFalse(Package."Volume Overridden", 'Volumet skal ikke lenger være overstyrt.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PackageTypeCopiesDefaults()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        Package: Record "nShift Package KBS";
        PackageType: Record "nShift Package Type KBS";
    begin
        CreateShipment(ShipmentHeader);
        PackageType.Init();
        PackageType.Code := 'NSHTEST';
        PackageType."Length (cm)" := 50;
        PackageType."Width (cm)" := 20;
        PackageType."Height (cm)" := 10;
        PackageType."Tare Weight (kg)" := 0.4;
        PackageType."Goods Type ID" := 7;
        PackageType.Insert();

        InitPackage(Package, ShipmentHeader, 10000);
        Package.Validate("Package Type Code", PackageType.Code);

        Assert.AreEqual(50, Package."Length (cm)", 'Lengde skal hentes fra kollitypen.');
        Assert.AreEqual(0.01, Package."Volume (m3)", 'Volum skal beregnes fra kollitypens mål.');
        Assert.AreEqual(0.4, Package."Weight (kg)", 'Taravekt skal brukes som startvekt.');
        Assert.AreEqual(7, Package."Goods Type ID", 'Godstype skal hentes fra kollitypen.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure HeaderFlowFieldsSumPackages()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
    begin
        CreateShipment(ShipmentHeader);
        InsertPackage(ShipmentHeader, 10000, 2.5, 0.1);
        InsertPackage(ShipmentHeader, 20000, 4, 0.25);

        ShipmentHeader.CalcFields("Total Weight (kg)", "Total Volume (m3)", "No. of Packages");
        Assert.AreEqual(6.5, ShipmentHeader."Total Weight (kg)", 'Total vekt skal summere kolliene.');
        Assert.AreEqual(0.35, ShipmentHeader."Total Volume (m3)", 'Totalt volum skal summere kolliene.');
        Assert.AreEqual(2, ShipmentHeader."No. of Packages", 'Antall kolli skal telle kolliene.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PackagesAreLockedAfterShipmentIsCreated()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        Package: Record "nShift Package KBS";
    begin
        CreateShipment(ShipmentHeader);
        ShipmentHeader.Status := ShipmentHeader.Status::Created;
        ShipmentHeader.Modify();

        InitPackage(Package, ShipmentHeader, 10000);
        asserterror Package.Insert(true);
        Assert.IsTrue(StrPos(GetLastErrorText(), ShipmentHeader."No.") > 0, 'Feilen skal nevne forsendelsen.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure CreatedShipmentCannotBeDeleted()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
    begin
        CreateShipment(ShipmentHeader);
        ShipmentHeader.Status := ShipmentHeader.Status::Created;
        ShipmentHeader.Modify();

        // asserterror ruller tilbake hele transaksjonen (også opprettelsen over), så sletteforsøket
        // kontrolleres via feilmeldingen – ikke ved å se etter posten etterpå.
        asserterror ShipmentHeader.Delete(true);
        Assert.IsTrue(GetLastErrorText().Contains('kan ikke slettes'), 'Sletting skal stoppes med forklaring: ' + GetLastErrorText());
        Assert.IsTrue(GetLastErrorText().Contains(ShipmentHeader."No."), 'Feilen skal nevne forsendelsen.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure DeletingOpenShipmentDeletesPackages()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        Package: Record "nShift Package KBS";
    begin
        CreateShipment(ShipmentHeader);
        InsertPackage(ShipmentHeader, 10000, 1, 0);

        ShipmentHeader.Delete(true);
        Package.SetRange("Shipment No.", ShipmentHeader."No.");
        Assert.IsTrue(Package.IsEmpty(), 'Kolliene skal slettes sammen med forsendelsen.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure ShipmentGetsNumberFromSeries()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
    begin
        CreateShipment(ShipmentHeader);
        Assert.IsTrue(ShipmentHeader."No." <> '', 'Forsendelsen skal få nummer fra nummerserien.');
    end;

    local procedure CreateShipment(var ShipmentHeader: Record "nShift Shipment Header KBS")
    var
        Install: Codeunit "nShift Install KBS";
    begin
        Install.InsertDefaults();
        ShipmentHeader.Init();
        ShipmentHeader.Insert(true);
    end;

    local procedure InitPackage(var Package: Record "nShift Package KBS"; ShipmentHeader: Record "nShift Shipment Header KBS"; LineNo: Integer)
    begin
        Package.Init();
        Package."Shipment No." := ShipmentHeader."No.";
        Package."Line No." := LineNo;
    end;

    local procedure InsertPackage(ShipmentHeader: Record "nShift Shipment Header KBS"; LineNo: Integer; Weight: Decimal; Volume: Decimal)
    var
        Package: Record "nShift Package KBS";
    begin
        InitPackage(Package, ShipmentHeader, LineNo);
        Package.Validate("Weight (kg)", Weight);
        if Volume <> 0 then
            Package.Validate("Volume (m3)", Volume);
        Package.Insert(true);
    end;
}
