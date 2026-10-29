namespace Knowit.nShift.Test;

using Knowit.nShift;

/// <summary>
/// Tester statusoverganger i «nShift Shipment Mgt. KBS» gjennom Ship-provideren og mocket HTTP.
/// Shipment Mgt. gjør Commit (for å kunne lagre status Feil), så testene bruker AutoCommit. Testkjøreren
/// (Isol. Codeunit) ruller tilbake etter hele codeuniten – derfor har hver test sitt eget forsendelsesnr.
/// </summary>
codeunit 73970 "nShift Shipment Mgt. Tests KBS"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "nShift Library Assert KBS";
        LibraryShipment: Codeunit "nShift Library Shipment KBS";
        HttpMock: Codeunit "nShift HTTP Mock KBS";
        ShipmentMgt: Codeunit "nShift Shipment Mgt. KBS";
        CreatedWithErrorJsonTok: Label '{"ShpTag":"TAG-HALF","ShpNo":"999","Lines":[{}],"Errors":[{"message":"Feil-etikett"}]}', Locked = true;
        DeletedJsonTok: Label '{"Messages":["Shipment has been deleted"]}', Locked = true;

    [Test]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure CreateSetsStatusCreated()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
    begin
        Initialize(ShipmentHeader, 'NSH-MGT01');
        EnqueueCreated();

        Assert.IsTrue(ShipmentMgt.CreateShipment(ShipmentHeader, TempLabelBuffer), 'Opprettelsen skal lykkes: ' + ShipmentHeader."Last Error Text");

        ShipmentHeader.Get(ShipmentHeader."No.");
        Assert.AreEqual(ShipmentHeader.Status::Created, ShipmentHeader.Status, 'Status skal være Opprettet.');
        Assert.IsTrue(ShipmentHeader."Tracking No." <> '', 'Sendingsnr. skal lagres.');
        Assert.IsTrue(ShipmentHeader."Tracking URL".StartsWith('http://sporing.bring.no/'), 'Sporingslenken skal hentes etter opprettelse.');
        Assert.IsTrue(ShipmentHeader."Sent to nShift At" <> 0DT, 'Tidspunktet skal lagres.');
        Assert.AreEqual('', ShipmentHeader."Last Error Text", 'Ingen feil.');
        Assert.AreEqual(1, TempLabelBuffer.Count(), 'Etiketten skal returneres til utskrift.');
        Finish();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure RejectedCreateSetsStatusError()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
    begin
        Initialize(ShipmentHeader, 'NSH-MGT02');
        HttpMock.EnqueueShipResponse(422, NavApp.GetResourceAsText('ship/error-invalid-weight.response.json'));

        Assert.IsFalse(ShipmentMgt.CreateShipment(ShipmentHeader, TempLabelBuffer), 'Avvist forsendelse skal gi false.');

        ShipmentHeader.Get(ShipmentHeader."No.");
        Assert.AreEqual(ShipmentHeader.Status::Error, ShipmentHeader.Status, 'Status skal være Feil.');
        Assert.IsTrue(ShipmentHeader."Last Error Text".Contains('35 kg'), 'Feilen fra nShift skal lagres: ' + ShipmentHeader."Last Error Text");
        Assert.IsTrue(ShipmentHeader.IsEditable(), 'Forsendelse med feil skal kunne rettes.');
        Finish();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure UnexpectedErrorIsCaughtAsStatusError()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
    begin
        Initialize(ShipmentHeader, 'NSH-MGT03');
        ShipmentHeader."Carrier Service Code" := '';
        ShipmentHeader.Modify();

        Assert.IsFalse(ShipmentMgt.CreateShipment(ShipmentHeader, TempLabelBuffer), 'Manglende tjeneste skal gi false, ikke stoppe kalleren.');

        ShipmentHeader.Get(ShipmentHeader."No.");
        Assert.AreEqual(ShipmentHeader.Status::Error, ShipmentHeader.Status, 'Status skal være Feil.');
        Assert.IsTrue(ShipmentHeader."Last Error Text".Contains('Uventet feil'), 'Feilen skal lagres: ' + ShipmentHeader."Last Error Text");
        Assert.AreEqual(0, HttpMock.GetShipCalls(), 'nShift skal ikke kalles.');
        Finish();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure HalfCreatedShipmentIsDeletedBeforeRetry()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
    begin
        Initialize(ShipmentHeader, 'NSH-MGT04');
        HttpMock.EnqueueShipResponse(201, CreatedWithErrorJsonTok);

        Assert.IsFalse(ShipmentMgt.CreateShipment(ShipmentHeader, TempLabelBuffer), '201 med feil skal gi false.');
        ShipmentHeader.Get(ShipmentHeader."No.");
        Assert.AreEqual(ShipmentHeader.Status::Error, ShipmentHeader.Status, 'Status skal være Feil.');
        Assert.AreEqual('TAG-HALF', ShipmentHeader."nShift Shipment Tag", 'ShpTag skal beholdes så forsendelsen kan slettes i nShift.');

        HttpMock.EnqueueShipResponse(200, DeletedJsonTok);
        EnqueueCreated();
        Assert.IsTrue(ShipmentMgt.RetryShipment(ShipmentHeader, TempLabelBuffer), 'Nytt forsøk skal lykkes: ' + ShipmentHeader."Last Error Text");

        Assert.IsTrue(HttpMock.GetShipRequest(2).StartsWith('DELETE '), 'Den halvveis opprettede forsendelsen skal slettes først: ' + HttpMock.GetShipRequest(2));
        Assert.IsTrue(HttpMock.GetShipRequest(2).EndsWith('/shipments/TAG-HALF'), 'Slettingen skal gjelde den gamle ShpTag.');
        Assert.IsTrue(HttpMock.GetShipRequest(3).StartsWith('POST '), 'Deretter opprettes den på nytt.');
        ShipmentHeader.Get(ShipmentHeader."No.");
        Assert.AreEqual(ShipmentHeader.Status::Created, ShipmentHeader.Status, 'Status skal være Opprettet.');
        Assert.AreEqual(1, ShipmentHeader."Retry Count", 'Antall forsøk skal telles.');
        Assert.IsTrue(ShipmentHeader."nShift Shipment Tag" <> 'TAG-HALF', 'Ny ShpTag skal lagres.');
        Finish();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure CreatedShipmentCannotBeCreatedAgain()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
    begin
        Initialize(ShipmentHeader, 'NSH-MGT05');
        SetStatus(ShipmentHeader, ShipmentHeader.Status::Created, 'TAG-5');

        asserterror ShipmentMgt.CreateShipment(ShipmentHeader, TempLabelBuffer);
        Assert.IsTrue(GetLastErrorText().Contains('kan ikke opprettes på nytt'), 'Feilen skal forklare hvorfor: ' + GetLastErrorText());
        Finish();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure RetryOnlyAllowedAfterError()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
    begin
        Initialize(ShipmentHeader, 'NSH-MGT06');

        asserterror ShipmentMgt.RetryShipment(ShipmentHeader, TempLabelBuffer);
        Assert.IsTrue(GetLastErrorText().Contains('status Feil'), 'Feilen skal forklare hvorfor: ' + GetLastErrorText());
        Finish();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure TransmitOnlyCreatedShipments()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        Created1: Record "nShift Shipment Header KBS";
        Created2: Record "nShift Shipment Header KBS";
        OpenShipment: Record "nShift Shipment Header KBS";
    begin
        Initialize(Created1, 'NSH-MGT07');
        SetStatus(Created1, Created1.Status::Created, 'TAG-7A');
        LibraryShipment.CreateShipment(Created2, 'NSH-MGT08');
        SetStatus(Created2, Created2.Status::Created, 'TAG-7B');
        LibraryShipment.CreateShipment(OpenShipment, 'NSH-MGT09');
        HttpMock.EnqueueShipResponse(200, '{}');

        ShipmentHeader.SetFilter("No.", 'NSH-MGT07..NSH-MGT09');
        Assert.AreEqual(2, ShipmentMgt.TransmitShipments(ShipmentHeader), 'Bare de to opprettede skal overføres.');

        Assert.IsTrue(HttpMock.GetLastShipRequestBody().Contains('"TAG-7A","TAG-7B"'), 'Begge ShpTag sendes i ett kall: ' + HttpMock.GetLastShipRequestBody());
        Created1.Get(Created1."No.");
        Assert.AreEqual(Created1.Status::Transmitted, Created1.Status, 'Første forsendelse skal være Overført.');
        Assert.IsTrue(Created1."Transmitted At" <> 0DT, 'Overføringstidspunkt skal lagres.');
        Created2.Get(Created2."No.");
        Assert.AreEqual(Created2.Status::Transmitted, Created2.Status, 'Andre forsendelse skal være Overført.');
        OpenShipment.Get(OpenShipment."No.");
        Assert.AreEqual(OpenShipment.Status::Open, OpenShipment.Status, 'Åpen forsendelse skal ikke røres.');
        Finish();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure FailedTransmitShowsError()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
    begin
        Initialize(ShipmentHeader, 'NSH-MGT10');
        SetStatus(ShipmentHeader, ShipmentHeader.Status::Created, 'TAG-10');
        HttpMock.EnqueueShipResponse(500, '{"ErrorType":"Internal Server Error","Message":"Boom","Errors":[]}');

        ShipmentHeader.SetRecFilter();
        asserterror ShipmentMgt.TransmitShipments(ShipmentHeader);
        Assert.IsTrue(GetLastErrorText().Contains('(500)'), 'Feilen fra nShift skal vises: ' + GetLastErrorText());
        Finish();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure CancelDeletesInNShiftAndResetsToOpen()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        Package: Record "nShift Package KBS";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
    begin
        Initialize(ShipmentHeader, 'NSH-MGT11');
        EnqueueCreated();
        ShipmentMgt.CreateShipment(ShipmentHeader, TempLabelBuffer);
        HttpMock.EnqueueShipResponse(200, DeletedJsonTok);

        ShipmentMgt.CancelShipment(ShipmentHeader);

        Assert.IsTrue(HttpMock.GetLastShipMethod() = 'DELETE', 'Forsendelsen skal slettes i nShift.');
        ShipmentHeader.Get(ShipmentHeader."No.");
        Assert.AreEqual(ShipmentHeader.Status::Open, ShipmentHeader.Status, 'Status skal tilbake til Åpen.');
        Assert.AreEqual('', ShipmentHeader."nShift Shipment Tag", 'ShpTag skal fjernes.');
        Assert.AreEqual('', ShipmentHeader."Tracking No.", 'Sendingsnr. skal fjernes.');
        Package.Get(ShipmentHeader."No.", 10000);
        Assert.AreEqual('', Package."Package Tracking No.", 'Kollinr. skal fjernes.');
        Package."Weight (kg)" := 10;
        Package.Modify();
        Finish();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure TransmittedShipmentCannotBeCancelled()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
    begin
        Initialize(ShipmentHeader, 'NSH-MGT12');
        SetStatus(ShipmentHeader, ShipmentHeader.Status::Transmitted, 'TAG-12');

        asserterror ShipmentMgt.CancelShipment(ShipmentHeader);
        Assert.IsTrue(GetLastErrorText().Contains('kan ikke kanselleres'), 'Feilen skal forklare hvorfor: ' + GetLastErrorText());
        Finish();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure LabelFormatComesFromPackingStation()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        PackingStation: Record "nShift Packing Station KBS";
        LocationSetup: Record "nShift Location Setup KBS";
    begin
        Initialize(ShipmentHeader, 'NSH-MGT13');
        LibraryShipment.ClearPackingStationDefaults();
        PackingStation.Init();
        PackingStation.Code := 'PS-ZPL';
        PackingStation."Location Code" := ShipmentHeader."Location Code";
        PackingStation."Label Format" := PackingStation."Label Format"::ZPL;
        if not PackingStation.Insert() then
            PackingStation.Modify();
        LocationSetup.Get(ShipmentHeader."Location Code");
        LocationSetup."Default Packing Station Code" := PackingStation.Code;
        LocationSetup.Modify();

        Assert.AreEqual("nShift Label Format KBS"::ZPL, ShipmentMgt.GetLabelFormat(ShipmentHeader), 'Pakkebordets format skal brukes.');
        Assert.AreEqual('PS-ZPL', ShipmentHeader."Packing Station Code", 'Pakkebordet skal settes på forsendelsen.');
        Finish();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure MockProviderCreatesWithoutHttp()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
        ProviderMock: Codeunit "nShift Provider Mock KBS";
    begin
        Initialize(ShipmentHeader, 'NSH-MGT14');
        UseMockProvider();
        ProviderMock.Reset();

        Assert.IsTrue(ShipmentMgt.CreateShipment(ShipmentHeader, TempLabelBuffer), 'Mock-provideren skal opprette: ' + ShipmentHeader."Last Error Text");

        Assert.AreEqual(1, ProviderMock.GetCreateCount(), 'Mock-provideren skal kalles én gang.');
        Assert.AreEqual(0, HttpMock.GetShipCalls(), 'Ingen HTTP-kall med mock-provider.');
        ShipmentHeader.Get(ShipmentHeader."No.");
        Assert.AreEqual('MOCK-NSH-MGT14', ShipmentHeader."nShift Shipment Tag", 'Mock-ShpTag skal lagres.');
        Assert.AreEqual(1, TempLabelBuffer.Count(), 'Én etikett per kolli.');
        Finish();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure MockProviderFailureSetsStatusError()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
        ProviderMock: Codeunit "nShift Provider Mock KBS";
    begin
        Initialize(ShipmentHeader, 'NSH-MGT15');
        UseMockProvider();
        ProviderMock.Reset();
        ProviderMock.SetCreateFailure('nShift er nede');

        Assert.IsFalse(ShipmentMgt.CreateShipment(ShipmentHeader, TempLabelBuffer), 'Feil fra provideren skal gi false.');

        ShipmentHeader.Get(ShipmentHeader."No.");
        Assert.AreEqual(ShipmentHeader.Status::Error, ShipmentHeader.Status, 'Status skal være Feil.');
        Assert.IsTrue(ShipmentHeader."Last Error Text".Contains('nShift er nede'), 'Feilen skal lagres: ' + ShipmentHeader."Last Error Text");
        ProviderMock.Reset();
        Finish();
    end;

    local procedure UseMockProvider()
    var
        Setup: Record "nShift Setup KBS";
    begin
        Setup.Get();
        Setup.Provider := Setup.Provider::"Mock KBS";
        Setup.Modify();
    end;

    local procedure Initialize(var ShipmentHeader: Record "nShift Shipment Header KBS"; ShipmentNo: Code[20])
    begin
        Clear(HttpMock);
        LibraryShipment.InitializeHttpMock(HttpMock);
        LibraryShipment.CreateShipment(ShipmentHeader, ShipmentNo);
    end;

    local procedure Finish()
    begin
        UnbindSubscription(HttpMock);
    end;

    local procedure EnqueueCreated()
    begin
        HttpMock.EnqueueShipResponse(201, NavApp.GetResourceAsText('ship/shipments-pdf.response.json'));
        HttpMock.EnqueueShipResponse(200, NavApp.GetResourceAsText('ship/trackingURL.response.json'));
    end;

    local procedure SetStatus(var ShipmentHeader: Record "nShift Shipment Header KBS"; NewStatus: Enum "nShift Shipment Status KBS"; ShipmentTag: Text[50])
    begin
        ShipmentHeader.Status := NewStatus;
        ShipmentHeader."nShift Shipment Tag" := ShipmentTag;
        ShipmentHeader.Modify();
    end;
}
