namespace Knowit.nShift.Test;

using Knowit.nShift;
using Microsoft.Sales.Document;
using Microsoft.Sales.History;

/// <summary>
/// Tester Fase 3 på logikknivå: kolli fra salgsordre, forslag, kontroll før bokføring, kobling til bokført følgeseddel
/// og opprettelse/utskrift etter bokføring med mock-provider og mock-skriver. Selve bokføringskjeden (lagerplukk →
/// Sales-Post) krever lager og varer og testes manuelt i sandkassen. AutoCommit fordi etterbehandlingen gjør Commit;
/// hver test bruker egne numre.
/// </summary>
codeunit 73975 "nShift Posting Tests KBS"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "nShift Library Assert KBS";
        LibraryShipment: Codeunit "nShift Library Shipment KBS";
        ProviderMock: Codeunit "nShift Provider Mock KBS";
        PrinterMock: Codeunit "nShift Printer Mock KBS";
        PackageMgt: Codeunit "nShift Package Mgt. KBS";
        PostingSubscribers: Codeunit "nShift Posting Subscribers KBS";
        LastMessage: Text;
        PackingStationCodeTok: Label 'PS-POST', Locked = true;

    [Test]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure ShipmentIsCreatedFromSalesOrder()
    var
        SalesHeader: Record "Sales Header";
        ShipmentHeader: Record "nShift Shipment Header KBS";
        SameShipment: Record "nShift Shipment Header KBS";
    begin
        Initialize();
        CreateSalesOrder(SalesHeader, 'NSH-SO01');

        PackageMgt.GetOrCreateForSalesOrder(SalesHeader, ShipmentHeader);

        Assert.AreEqual(ShipmentHeader."Source Document Type"::"Sales Order", ShipmentHeader."Source Document Type", 'Kilden er salgsordren.');
        Assert.AreEqual('NSH-SO01', ShipmentHeader."Sales Order No.", 'Salgsordren lagres.');
        Assert.AreEqual(LibraryShipment.GetCarrierServiceCode(), ShipmentHeader."Carrier Service Code", 'Tjenesten hentes fra ordren.');
        Assert.AreEqual('Testkunde AS', ShipmentHeader."Ship-to Name", 'Leveringsadressen kopieres.');
        Assert.AreEqual('+4790000000', ShipmentHeader."Ship-to Mobile Phone No.", 'Telefon brukes som mobil for SMS-varsling.');
        Assert.AreEqual('PO-4711', ShipmentHeader.Reference, 'Deres referanse blir referanse.');
        Assert.AreEqual('Ring før levering', ShipmentHeader."Delivery Instructions", 'Leveringsinstruksen kopieres.');
        SalesHeader.Get(SalesHeader."Document Type", SalesHeader."No.");
        Assert.AreEqual(ShipmentHeader."No.", SalesHeader."nShift Shipment No. KBS", 'Ordren kobles til forsendelsen.');

        PackageMgt.GetOrCreateForSalesOrder(SalesHeader, SameShipment);
        Assert.AreEqual(ShipmentHeader."No.", SameShipment."No.", 'Samme åpne forsendelse brukes igjen.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure PackagesAreAddedFromPackageType()
    var
        SalesHeader: Record "Sales Header";
        ShipmentHeader: Record "nShift Shipment Header KBS";
        Package: Record "nShift Package KBS";
    begin
        Initialize();
        CreateSalesOrder(SalesHeader, 'NSH-SO02');
        PackageMgt.GetOrCreateForSalesOrder(SalesHeader, ShipmentHeader);

        PackageMgt.AddPackages(ShipmentHeader, 'ESKE', 3, 2.5);

        Package.SetRange("Shipment No.", ShipmentHeader."No.");
        Assert.AreEqual(3, Package.Count(), 'Tre kolli skal legges til.');
        Package.FindFirst();
        Assert.AreEqual(2.5, Package."Weight (kg)", 'Vekt per kolli brukes.');
        Assert.AreEqual(40, Package."Length (cm)", 'Mål hentes fra kollitypen.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure SuggestedPackagesRespectMaxWeight()
    var
        SalesHeader: Record "Sales Header";
        ShipmentHeader: Record "nShift Shipment Header KBS";
        CarrierService: Record "nShift Carrier Service KBS";
        Package: Record "nShift Package KBS";
    begin
        Initialize();
        CreateSalesOrder(SalesHeader, 'NSH-SO03');
        AddSalesLine(SalesHeader, 10000, 5, 10);
        CarrierService.Get(LibraryShipment.GetCarrierServiceCode());
        CarrierService."Max Weight (kg)" := 35;
        CarrierService.Modify();
        PackageMgt.GetOrCreateForSalesOrder(SalesHeader, ShipmentHeader);

        Assert.AreEqual(2, PackageMgt.SuggestPackages(ShipmentHeader), '50 kg med maks. 35 kg gir to kolli.');

        Package.SetRange("Shipment No.", ShipmentHeader."No.");
        Package.FindFirst();
        Assert.AreEqual(25, Package."Weight (kg)", 'Vekten fordeles likt.');
        CarrierService."Max Weight (kg)" := 0;
        CarrierService.Modify();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure SuggestWithoutGrossWeightGivesError()
    var
        SalesHeader: Record "Sales Header";
        ShipmentHeader: Record "nShift Shipment Header KBS";
    begin
        Initialize();
        CreateSalesOrder(SalesHeader, 'NSH-SO04');
        AddSalesLine(SalesHeader, 10000, 5, 0);
        PackageMgt.GetOrCreateForSalesOrder(SalesHeader, ShipmentHeader);

        asserterror PackageMgt.SuggestPackages(ShipmentHeader);
        Assert.IsTrue(GetLastErrorText().Contains('bruttovekt'), 'Feilen skal forklare at bruttovekt mangler: ' + GetLastErrorText());
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure ValidationBeforePostingFindsProblems()
    var
        SalesHeader: Record "Sales Header";
        ShipmentHeader: Record "nShift Shipment Header KBS";
        Package: Record "nShift Package KBS";
        CarrierService: Record "nShift Carrier Service KBS";
        ErrorText: Text;
    begin
        Initialize();
        CreateSalesOrder(SalesHeader, 'NSH-SO05');
        PackageMgt.GetOrCreateForSalesOrder(SalesHeader, ShipmentHeader);

        Assert.IsFalse(PackageMgt.ValidateForPosting(ShipmentHeader, ErrorText), 'Uten kolli er forsendelsen ikke klar.');
        Assert.IsTrue(ErrorText.Contains('ingen kolli'), 'Feil: ' + ErrorText);

        PackageMgt.AddPackages(ShipmentHeader, 'ESKE', 1, 0);
        Package.SetRange("Shipment No.", ShipmentHeader."No.");
        Package.FindFirst();
        Package."Weight (kg)" := 0;
        Package.Modify();
        Assert.IsFalse(PackageMgt.ValidateForPosting(ShipmentHeader, ErrorText), 'Kolli uten vekt skal stoppes.');
        Assert.IsTrue(ErrorText.Contains('mangler vekt'), 'Feil: ' + ErrorText);

        Package."Weight (kg)" := 40;
        Package.Modify();
        CarrierService.Get(ShipmentHeader."Carrier Service Code");
        CarrierService."Max Weight (kg)" := 35;
        CarrierService.Modify();
        Assert.IsFalse(PackageMgt.ValidateForPosting(ShipmentHeader, ErrorText), 'For tungt kolli skal stoppes.');
        Assert.IsTrue(ErrorText.Contains('maks. 35 kg'), 'Feil: ' + ErrorText);

        Package."Weight (kg)" := 20;
        Package.Modify();
        Assert.IsTrue(PackageMgt.ValidateForPosting(ShipmentHeader, ErrorText), 'Gyldig forsendelse: ' + ErrorText);
        CarrierService."Max Weight (kg)" := 0;
        CarrierService.Modify();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure PostingRequiresPackagesWhenSetupSaysSo()
    var
        SalesHeader: Record "Sales Header";
        Setup: Record "nShift Setup KBS";
    begin
        Initialize();
        CreateSalesOrder(SalesHeader, 'NSH-SO06');
        SalesHeader.Ship := true;
        Setup.Get();
        Setup."Require Packages on Posting" := true;
        Setup.Modify();

        asserterror PackageMgt.CheckSalesOrderBeforePosting(SalesHeader);
        Assert.IsTrue(GetLastErrorText().Contains('ingen registrerte kolli'), 'Bokføring uten kolli skal stoppes: ' + GetLastErrorText());
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure ShipAndInvoiceIsStoppedForNShiftOrder()
    var
        SalesHeader: Record "Sales Header";
        ShipmentHeader: Record "nShift Shipment Header KBS";
    begin
        Initialize();
        CreateSalesOrder(SalesHeader, 'NSH-SO11');
        PackageMgt.GetOrCreateForSalesOrder(SalesHeader, ShipmentHeader);
        PackageMgt.AddPackages(ShipmentHeader, 'ESKE', 1, 5);
        SalesHeader.Get(SalesHeader."Document Type", SalesHeader."No.");
        SalesHeader.Ship := true;
        SalesHeader.Invoice := true;

        asserterror PackageMgt.CheckSalesOrderBeforePosting(SalesHeader);
        Assert.IsTrue(GetLastErrorText().Contains('leveres og faktureres'), 'Lever og fakturer skal stoppes: ' + GetLastErrorText());
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure PostedShipmentGetsPackageTotalsAndLink()
    var
        SalesHeader: Record "Sales Header";
        ShipmentHeader: Record "nShift Shipment Header KBS";
        TempSalesShipmentHeader: Record "Sales Shipment Header" temporary;
    begin
        Initialize();
        CreateSalesOrder(SalesHeader, 'NSH-SO07');
        PackageMgt.GetOrCreateForSalesOrder(SalesHeader, ShipmentHeader);
        PackageMgt.AddPackages(ShipmentHeader, 'ESKE', 2, 3);
        SalesHeader.Get(SalesHeader."Document Type", SalesHeader."No.");
        TempSalesShipmentHeader.Init();
        TempSalesShipmentHeader."No." := 'NSH-PS07';

        PostingSubscribers.LinkShipmentToPostedShipment(TempSalesShipmentHeader, SalesHeader);

        Assert.AreEqual(ShipmentHeader."No.", TempSalesShipmentHeader."nShift Shipment No. KBS", 'Forsendelsesnr. kopieres til følgeseddelen.');
        Assert.AreEqual(2, TempSalesShipmentHeader."nShift No. of Packages KBS", 'Antall kolli kopieres.');
        Assert.AreEqual(6, TempSalesShipmentHeader."nShift Total Weight KBS", 'Totalvekt kopieres.');
        ShipmentHeader.Get(ShipmentHeader."No.");
        Assert.AreEqual('NSH-PS07', ShipmentHeader."Posted Shipment No.", 'Forsendelsen kobles til følgeseddelen.');
        Assert.AreEqual(ShipmentHeader."Source Document Type"::"Posted Sales Shipment", ShipmentHeader."Source Document Type", 'Kilden blir den bokførte følgeseddelen.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure AfterPostingShipmentIsCreatedAndPrinted()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        SalesHeader: Record "Sales Header";
    begin
        Initialize();
        CreatePostedShipment(ShipmentHeader, 'NSH-SO08', 'NSH-PS08');

        PostingSubscribers.ProcessPostedShipment(ShipmentHeader);

        ShipmentHeader.Get(ShipmentHeader."No.");
        Assert.AreEqual(ShipmentHeader.Status::Created, ShipmentHeader.Status, 'Forsendelsen skal opprettes i nShift etter bokføring.');
        Assert.AreEqual(1, ProviderMock.GetCreateCount(), 'nShift skal kalles én gang.');
        Assert.AreEqual(1, PrinterMock.GetPrintCount(), 'Etiketten skal skrives ut.');
        Assert.AreEqual(PackingStationCodeTok, PrinterMock.GetLastPackingStationCode(), 'Pakkebordets skriver brukes.');
        // Sporingsnr. til den bokførte følgeseddelen kontrolleres i manuell bokføringstest: testkode kan ikke opprette
        // bokførte følgesedler (bare Sales-Post har indirekte tillatelse).
        SalesHeader.Get(SalesHeader."Document Type"::Order, 'NSH-SO08');
        Assert.AreEqual(ShipmentHeader."Tracking No.", SalesHeader."Package Tracking No.", 'Sporingsnr. skrives til salgsordren.');
    end;

    [Test]
    [HandlerFunctions('MessageHandler')]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure NShiftErrorAfterPostingDoesNotStopPosting()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
    begin
        Initialize();
        CreatePostedShipment(ShipmentHeader, 'NSH-SO09', 'NSH-PS09');
        ProviderMock.SetCreateFailure('nShift er nede');

        PostingSubscribers.ProcessPostedShipment(ShipmentHeader);

        ShipmentHeader.Get(ShipmentHeader."No.");
        Assert.AreEqual(ShipmentHeader.Status::Error, ShipmentHeader.Status, 'Forsendelsen får status Feil.');
        Assert.IsTrue(LastMessage.Contains('nShift er nede'), 'Brukeren får melding om feilen: ' + LastMessage);
        Assert.IsTrue(LastMessage.Contains('bokført'), 'Meldingen sier at følgeseddelen er bokført: ' + LastMessage);
        Assert.AreEqual(0, PrinterMock.GetPrintCount(), 'Ingen utskrift når forsendelsen ikke ble opprettet.');
        ProviderMock.Reset();
    end;

    [Test]
    [HandlerFunctions('MessageHandler')]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure PrinterErrorAfterPostingKeepsShipmentCreated()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
    begin
        Initialize();
        CreatePostedShipment(ShipmentHeader, 'NSH-SO10', 'NSH-PS10');
        PrinterMock.SetFailure('Skriveren er frakoblet');

        PostingSubscribers.ProcessPostedShipment(ShipmentHeader);

        ShipmentHeader.Get(ShipmentHeader."No.");
        Assert.AreEqual(ShipmentHeader.Status::Created, ShipmentHeader.Status, 'Forsendelsen er opprettet selv om utskriften feilet.');
        Assert.IsTrue(ShipmentHeader."Last Error Text".Contains('Skriveren er frakoblet'), 'Utskriftsfeilen lagres: ' + ShipmentHeader."Last Error Text");
        Assert.IsTrue(LastMessage.Contains('Skriveren er frakoblet'), 'Brukeren får melding om utskriftsfeilen: ' + LastMessage);
        PrinterMock.Reset();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure TransmitJobSendsAllCreatedShipments()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        AllShipments: Record "nShift Shipment Header KBS";
        TransmitShipments: Codeunit "nShift Transmit Shipments KBS";
    begin
        Initialize();
        LibraryShipment.CreateShipment(ShipmentHeader, 'NSH-TRM1');
        SetCreated(ShipmentHeader);
        LibraryShipment.CreateShipment(ShipmentHeader, 'NSH-TRM2');
        SetCreated(ShipmentHeader);

        AllShipments.SetFilter("No.", 'NSH-TRM1|NSH-TRM2');
        Assert.AreEqual(2, TransmitShipments.TransmitAllCreated(AllShipments), 'Begge opprettede forsendelser overføres.');
        Assert.AreEqual(1, ProviderMock.GetTransmitCount(), 'I ett kall til nShift.');
        ShipmentHeader.Get('NSH-TRM1');
        Assert.AreEqual(ShipmentHeader.Status::Transmitted, ShipmentHeader.Status, 'Status blir Overført.');
    end;

    [MessageHandler]
    procedure MessageHandler(Message: Text[1024])
    begin
        LastMessage := Message;
    end;

    local procedure Initialize()
    var
        Setup: Record "nShift Setup KBS";
        PackingStation: Record "nShift Packing Station KBS";
        ShipmentHeader: Record "nShift Shipment Header KBS";
        Install: Codeunit "nShift Install KBS";
    begin
        LastMessage := '';
        Install.InsertDefaults();
        // Kjør bibliotekets oppsett (land, lokasjon, tjeneste) via en midlertidig forsendelse.
        if not ShipmentHeader.Get('NSH-POSTLIB') then
            LibraryShipment.CreateShipment(ShipmentHeader, 'NSH-POSTLIB');
        Setup.Get();
        Setup.Provider := Setup.Provider::"Mock KBS";
        Setup."Require Packages on Posting" := false;
        Setup."Store Label as Attachment" := false;
        Setup.Modify();
        PackingStation.Init();
        PackingStation.Code := PackingStationCodeTok;
        PackingStation."Printer Provider" := PackingStation."Printer Provider"::"Mock KBS";
        PackingStation."Printer ID" := 'MOCK-1';
        if not PackingStation.Insert() then
            PackingStation.Modify();
        ProviderMock.Reset();
        PrinterMock.Reset();
    end;

    local procedure CreateSalesOrder(var SalesHeader: Record "Sales Header"; OrderNo: Code[20])
    var
        LibraryShipmentHeader: Record "nShift Shipment Header KBS";
    begin
        LibraryShipmentHeader.Get('NSH-POSTLIB');
        SalesHeader.Init();
        SalesHeader."Document Type" := SalesHeader."Document Type"::Order;
        SalesHeader."No." := OrderNo;
        SalesHeader."Sell-to Customer No." := 'K10000';
        SalesHeader."Ship-to Name" := 'Testkunde AS';
        SalesHeader."Ship-to Address" := 'Storgata 1';
        SalesHeader."Ship-to Post Code" := '0155';
        SalesHeader."Ship-to City" := 'OSLO';
        SalesHeader."Ship-to Country/Region Code" := 'NO';
        SalesHeader."Ship-to Phone No." := '+4790000000';
        SalesHeader."Sell-to E-Mail" := 'test@example.no';
        SalesHeader."Your Reference" := 'PO-4711';
        SalesHeader."Location Code" := LibraryShipmentHeader."Location Code";
        SalesHeader."nShift Carrier Service KBS" := LibraryShipment.GetCarrierServiceCode();
        SalesHeader."nShift Delivery Instr. KBS" := 'Ring før levering';
        SalesHeader."nShift Packing Station KBS" := PackingStationCodeTok;
        SalesHeader.Insert();
    end;

    local procedure AddSalesLine(SalesHeader: Record "Sales Header"; LineNo: Integer; QtyToShip: Decimal; GrossWeight: Decimal)
    var
        SalesLine: Record "Sales Line";
    begin
        SalesLine.Init();
        SalesLine."Document Type" := SalesHeader."Document Type";
        SalesLine."Document No." := SalesHeader."No.";
        SalesLine."Line No." := LineNo;
        SalesLine.Type := SalesLine.Type::Item;
        SalesLine."Qty. to Ship" := QtyToShip;
        SalesLine."Gross Weight" := GrossWeight;
        SalesLine.Insert();
    end;

    /// <summary>
    /// Salgsordre med åpen forsendelse og kolli, koblet til en bokført følgeseddel – slik den står etter bokføring.
    /// Følgeseddelen er midlertidig: bare Sales-Post kan opprette bokførte følgesedler (indirekte tillatelse).
    /// </summary>
    local procedure CreatePostedShipment(var ShipmentHeader: Record "nShift Shipment Header KBS"; OrderNo: Code[20]; PostedShipmentNo: Code[20])
    var
        SalesHeader: Record "Sales Header";
        TempSalesShipmentHeader: Record "Sales Shipment Header" temporary;
    begin
        CreateSalesOrder(SalesHeader, OrderNo);
        PackageMgt.GetOrCreateForSalesOrder(SalesHeader, ShipmentHeader);
        PackageMgt.AddPackages(ShipmentHeader, 'ESKE', 1, 5);
        SalesHeader.Get(SalesHeader."Document Type", SalesHeader."No.");
        TempSalesShipmentHeader.Init();
        TempSalesShipmentHeader."No." := PostedShipmentNo;
        PostingSubscribers.LinkShipmentToPostedShipment(TempSalesShipmentHeader, SalesHeader);
        ShipmentHeader.Get(ShipmentHeader."No.");
    end;

    local procedure SetCreated(var ShipmentHeader: Record "nShift Shipment Header KBS")
    begin
        ShipmentHeader.Status := ShipmentHeader.Status::Created;
        ShipmentHeader."nShift Shipment Tag" := 'MOCK-' + ShipmentHeader."No.";
        ShipmentHeader.Modify();
    end;
}
