namespace Knowit.nShift.Test;

using Knowit.nShift;

/// <summary>
/// Tester «nShift Ship Provider KBS» ende til ende gjennom API-klienten, med mocket HTTP og svar fra fixtures.
/// Hver test kontrollerer både hva som sendes (metode, URL, innhold) og hvordan svaret leses.
/// </summary>
codeunit 73969 "nShift Ship Provider Tests KBS"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "nShift Library Assert KBS";
        LibraryShipment: Codeunit "nShift Library Shipment KBS";
        HttpMock: Codeunit "nShift HTTP Mock KBS";
        ShipProvider: Codeunit "nShift Ship Provider KBS";
        ShipmentNoTok: Label 'NSH-PRV1', Locked = true;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure CreateShipmentSendsRequestAndReadsResponse()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        Package: Record "nShift Package KBS";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
        Response: JsonObject;
        ErrorText: Text;
    begin
        Initialize(ShipmentHeader);
        HttpMock.EnqueueShipResponse(201, NavApp.GetResourceAsText('ship/shipments-pdf.response.json'));
        Response.ReadFrom(NavApp.GetResourceAsText('ship/shipments-pdf.response.json'));

        Assert.IsTrue(ShipProvider.CreateShipment(ShipmentHeader, "nShift Label Format KBS"::PDF, TempLabelBuffer, ErrorText), 'Opprettelsen skal lykkes: ' + ErrorText);

        Assert.AreEqual('POST', HttpMock.GetLastShipMethod(), 'Opprettelse er POST.');
        Assert.IsTrue(HttpMock.GetLastShipUrl().EndsWith('/ShipServer/13131/shipments'), 'Opprettelse går til /shipments.');
        Assert.IsTrue(HttpMock.GetLastShipRequestBody().Contains('"Labels":"PDF"'), 'Etikett i PDF skal bestilles.');
        Assert.AreEqual(GetText(Response, 'ShpTag'), ShipmentHeader."nShift Shipment Tag", 'ShpTag skal settes.');
        Assert.AreEqual(GetText(Response, 'ShpNo'), ShipmentHeader."Tracking No.", 'Sendingsnr. skal settes.');
        Package.Get(ShipmentHeader."No.", 10000);
        Assert.IsTrue(Package."Package Tracking No." <> '', 'Kollinr. skal settes.');
        Assert.AreEqual(1, TempLabelBuffer.Count(), 'Etiketten skal returneres.');
        UnbindSubscription(HttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure CreateShipmentRejectedGivesNShiftMessage()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
        ErrorText: Text;
    begin
        Initialize(ShipmentHeader);
        HttpMock.EnqueueShipResponse(422, NavApp.GetResourceAsText('ship/error-invalid-weight.response.json'));

        Assert.IsFalse(ShipProvider.CreateShipment(ShipmentHeader, "nShift Label Format KBS"::PDF, TempLabelBuffer, ErrorText), '422 skal gi false.');
        Assert.IsTrue(ErrorText.Contains('35 kg'), 'nShift sin valideringsfeil skal vises: ' + ErrorText);
        Assert.AreEqual('', ShipmentHeader."nShift Shipment Tag", 'Ingen ShpTag når forsendelsen ble avvist.');
        UnbindSubscription(HttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure ValidateShipmentSendsWithoutLabels()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        ErrorText: Text;
    begin
        Initialize(ShipmentHeader);
        HttpMock.EnqueueShipResponse(200, NavApp.GetResourceAsText('ship/shipmentValidations.response.json'));

        Assert.IsTrue(ShipProvider.ValidateShipment(ShipmentHeader, ErrorText), 'Valideringen skal lykkes: ' + ErrorText);
        Assert.IsTrue(HttpMock.GetLastShipUrl().EndsWith('/shipmentValidations'), 'Validering går til /shipmentValidations.');
        Assert.IsTrue(HttpMock.GetLastShipRequestBody().Contains('"Labels":"none"'), 'Validering skal ikke bestille etikett.');
        UnbindSubscription(HttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure TransmitSendsAllShipmentTagsInOneCall()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        ErrorText: Text;
    begin
        Initialize(ShipmentHeader);
        SetShipmentTag(ShipmentHeader, 'TAG-A');
        LibraryShipment.CreateShipment(ShipmentHeader, 'NSH-PRV2');
        SetShipmentTag(ShipmentHeader, 'TAG-B');
        LibraryShipment.CreateShipment(ShipmentHeader, 'NSH-PRV3');
        HttpMock.EnqueueShipResponse(200, '{}');

        ShipmentHeader.SetFilter("No.", '%1|%2|%3', ShipmentNoTok, 'NSH-PRV2', 'NSH-PRV3');
        Assert.IsTrue(ShipProvider.TransmitShipments(ShipmentHeader, ErrorText), 'Overføringen skal lykkes: ' + ErrorText);

        Assert.AreEqual(1, HttpMock.GetShipCalls(), 'Alle forsendelser overføres i ett kall.');
        Assert.AreEqual('PUT', HttpMock.GetLastShipMethod(), 'Manifest er PUT.');
        Assert.IsTrue(HttpMock.GetLastShipUrl().EndsWith('/shipments/manifest'), 'Overføring går til /shipments/manifest.');
        Assert.AreEqual('{"data":{"ShipmentTags":["TAG-A","TAG-B"]},"options":{}}', HttpMock.GetLastShipRequestBody(), 'Bare forsendelser med ShpTag sendes.');
        UnbindSubscription(HttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure TransmitWithoutCreatedShipmentsIsRejected()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        ErrorText: Text;
    begin
        Initialize(ShipmentHeader);
        ShipmentHeader.SetRecFilter();

        Assert.IsFalse(ShipProvider.TransmitShipments(ShipmentHeader, ErrorText), 'Uten ShpTag er det ingenting å overføre.');
        Assert.AreEqual(0, HttpMock.GetShipCalls(), 'nShift skal ikke kalles.');
        Assert.IsTrue(ErrorText.Contains('ingenting kan overføres'), 'Meldingen skal forklare hvorfor: ' + ErrorText);
        UnbindSubscription(HttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure DeleteUsesShipmentTag()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        ErrorText: Text;
    begin
        Initialize(ShipmentHeader);
        SetShipmentTag(ShipmentHeader, 'TAG-DEL');
        HttpMock.EnqueueShipResponse(200, NavApp.GetResourceAsText('ship/shipment-delete.response.json'));

        Assert.IsTrue(ShipProvider.DeleteShipment(ShipmentHeader, ErrorText), 'Slettingen skal lykkes: ' + ErrorText);
        Assert.AreEqual('DELETE', HttpMock.GetLastShipMethod(), 'Sletting er DELETE.');
        Assert.IsTrue(HttpMock.GetLastShipUrl().EndsWith('/shipments/TAG-DEL'), 'Sletting adresseres med ShpTag.');
        UnbindSubscription(HttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure ShipmentNotInNShiftCannotBeDeleted()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        ErrorText: Text;
    begin
        Initialize(ShipmentHeader);

        Assert.IsFalse(ShipProvider.DeleteShipment(ShipmentHeader, ErrorText), 'Uten ShpTag kan ikke forsendelsen slettes i nShift.');
        Assert.AreEqual(0, HttpMock.GetShipCalls(), 'nShift skal ikke kalles.');
        Assert.IsTrue(ErrorText.Contains(ShipmentNoTok), 'Meldingen skal nevne forsendelsen.');
        UnbindSubscription(HttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure RefreshReadsShipmentFromNShift()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        Response: JsonObject;
        ErrorText: Text;
    begin
        Initialize(ShipmentHeader);
        Response.ReadFrom(NavApp.GetResourceAsText('ship/shipment-get.response.json'));
        SetShipmentTag(ShipmentHeader, GetText(Response, 'ShpTag'));
        HttpMock.EnqueueShipResponse(200, NavApp.GetResourceAsText('ship/shipment-get.response.json'));

        Assert.IsTrue(ShipProvider.RefreshShipment(ShipmentHeader, ErrorText), 'Oppslaget skal lykkes: ' + ErrorText);
        Assert.AreEqual('GET', HttpMock.GetLastShipMethod(), 'Oppslag er GET.');
        Assert.AreEqual(GetText(Response, 'ShpNo'), ShipmentHeader."Tracking No.", 'Sendingsnr. skal oppdateres.');
        Assert.AreEqual(GetText(Response, 'ShpCSID'), Format(ShipmentHeader."nShift ShpCSID", 0, 9), 'ShpCSID skal oppdateres.');
        UnbindSubscription(HttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure ReprintRequestsLabelsByShpCSID()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
        ErrorText: Text;
    begin
        Initialize(ShipmentHeader);
        ShipmentHeader."nShift ShpCSID" := 767918497;
        HttpMock.EnqueueShipResponse(200, NavApp.GetResourceAsText('ship/labelReprint.response.json'));

        Assert.IsTrue(ShipProvider.ReprintLabels(ShipmentHeader, "nShift Label Format KBS"::ZPL, TempLabelBuffer, ErrorText), 'Ny utskrift skal lykkes: ' + ErrorText);
        Assert.IsTrue(HttpMock.GetLastShipUrl().EndsWith('/shipments/labelReprint'), 'Ny utskrift går til /shipments/labelReprint.');
        Assert.AreEqual('{"data":{"ShpCSID":767918497},"options":{"Labels":"ZPLGK"}}', HttpMock.GetLastShipRequestBody(), 'ShpCSID og ønsket format sendes.');
        Assert.AreEqual(1, TempLabelBuffer.Count(), 'Etiketten skal returneres.');
        UnbindSubscription(HttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure TrackingUrlIsStored()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        ErrorText: Text;
    begin
        Initialize(ShipmentHeader);
        SetShipmentTag(ShipmentHeader, 'TAG-TRK');
        HttpMock.EnqueueShipResponse(200, NavApp.GetResourceAsText('ship/trackingURL.response.json'));

        Assert.IsTrue(ShipProvider.GetTrackingUrl(ShipmentHeader, ErrorText), 'Sporingslenken skal hentes: ' + ErrorText);
        Assert.IsTrue(HttpMock.GetLastShipUrl().EndsWith('/shipments/TAG-TRK/trackingURL'), 'Sporing adresseres med ShpTag.');
        Assert.IsTrue(ShipmentHeader."Tracking URL".StartsWith('http://sporing.bring.no/'), 'Sporingslenken skal lagres.');
        UnbindSubscription(HttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure DeactivatedPriceCalculationGivesReadableError()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        Price: Decimal;
        ErrorText: Text;
    begin
        Initialize(ShipmentHeader);
        HttpMock.EnqueueShipResponse(200, NavApp.GetResourceAsText('ship/shipmentPrices.response.json'));

        Assert.IsFalse(ShipProvider.GetPrice(ShipmentHeader, Price, ErrorText), 'HTTP 200 med StatusCode 19 er ingen pris.');
        Assert.AreEqual(0, Price, 'Prisen skal være 0.');
        Assert.IsTrue(ErrorText.Contains('Calculation is deactivated'), 'Forklaringen fra HTML-svaret skal vises: ' + ErrorText);
        Assert.IsFalse(ErrorText.Contains('<'), 'HTML-tagger skal fjernes: ' + ErrorText);
        Assert.IsTrue(HttpMock.GetLastShipUrl().EndsWith('/shipmentPrices'), 'Pris går til /shipmentPrices.');
        Assert.IsFalse(HttpMock.GetLastShipRequestBody().Contains('"options"'), 'Prisforespørselen har bare data.');
        UnbindSubscription(HttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PriceIsReadWhenCalculated()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        Price: Decimal;
        ErrorText: Text;
    begin
        Initialize(ShipmentHeader);
        // Konstruert svar – vellykket pris er ikke tatt opp ennå (prisberegning deaktivert, TASKS 2.1.6).
        HttpMock.EnqueueShipResponse(200, '{"ListPrice":250.5,"Price1":199.0,"Currency":0,"Price2":0.0,"Currency2":0,"StatusCode":0,"StatusMsg":""}');

        Assert.IsTrue(ShipProvider.GetPrice(ShipmentHeader, Price, ErrorText), 'Prisen skal leses: ' + ErrorText);
        Assert.AreEqual(199, Price, 'Price1 brukes når den er satt.');
        UnbindSubscription(HttpMock);
    end;

    local procedure Initialize(var ShipmentHeader: Record "nShift Shipment Header KBS")
    begin
        Clear(HttpMock);
        LibraryShipment.InitializeHttpMock(HttpMock);
        LibraryShipment.CreateShipment(ShipmentHeader, ShipmentNoTok);
    end;

    local procedure SetShipmentTag(var ShipmentHeader: Record "nShift Shipment Header KBS"; ShipmentTag: Text)
    begin
        ShipmentHeader."nShift Shipment Tag" := CopyStr(ShipmentTag, 1, MaxStrLen(ShipmentHeader."nShift Shipment Tag"));
        ShipmentHeader.Modify();
    end;

    local procedure GetText(Source: JsonObject; KeyName: Text): Text
    var
        Token: JsonToken;
    begin
        Source.Get(KeyName, Token);
        exit(Token.AsValue().AsText());
    end;
}
