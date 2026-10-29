namespace Knowit.nShift.Test;

using Knowit.nShift;

/// <summary>
/// Tester «nShift Ship Shpt. Mapper KBS» mot request/respons tatt opp fra nShift (Test/fixtures/ship).
/// Testforsendelsen speiler FIXTURE-PDF, slik at JSON-en kan sammenlignes felt for felt med requesten nShift godtok.
/// </summary>
codeunit 73967 "nShift Ship Mapper Tests KBS"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "nShift Library Assert KBS";
        LibraryShipment: Codeunit "nShift Library Shipment KBS";
        ShipmentNoTok: Label 'NSH-MAP1', Locked = true;
        CarrierServiceCodeTok: Label 'BRING-PAKKE', Locked = true;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure RequestMatchesRecordedRequest()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        Mapper: Codeunit "nShift Ship Shpt. Mapper KBS";
        Built: JsonObject;
        Recorded: JsonObject;
    begin
        LibraryShipment.CreateShipment(ShipmentHeader, ShipmentNoTok);

        Built := Mapper.BuildShipmentRequest(ShipmentHeader, "nShift Label Format KBS"::PDF, true);

        Recorded.ReadFrom(NavApp.GetResourceAsText('ship/shipments-pdf.request.json'));
        AssertSamePath(Built, Recorded, '$.data.Kind');
        AssertSamePath(Built, Recorded, '$.data.ProdConceptID');
        AssertSamePath(Built, Recorded, '$.data.OrderNo');
        AssertSamePath(Built, Recorded, '$.data.Addresses[0].Kind');
        AssertSamePath(Built, Recorded, '$.data.Addresses[0].Name1');
        AssertSamePath(Built, Recorded, '$.data.Addresses[0].Street1');
        AssertSamePath(Built, Recorded, '$.data.Addresses[0].PostCode');
        AssertSamePath(Built, Recorded, '$.data.Addresses[0].City');
        AssertSamePath(Built, Recorded, '$.data.Addresses[0].CountryCode');
        AssertSamePath(Built, Recorded, '$.data.Addresses[0].Mobile');
        AssertSamePath(Built, Recorded, '$.data.Addresses[0].Email');
        AssertSamePath(Built, Recorded, '$.data.Addresses[0].Attention');
        AssertSamePath(Built, Recorded, '$.data.Addresses[0].ERPRef');
        AssertSamePath(Built, Recorded, '$.data.Addresses[1].Kind');
        AssertSamePath(Built, Recorded, '$.data.Addresses[1].Name1');
        AssertSamePath(Built, Recorded, '$.data.Addresses[1].PostCode');
        AssertSamePath(Built, Recorded, '$.data.Addresses[1].CountryCode');
        AssertSamePath(Built, Recorded, '$.data.Lines[0].Number');
        AssertSamePath(Built, Recorded, '$.data.Lines[0].PkgWeight');
        AssertSamePath(Built, Recorded, '$.data.Lines[0].LineWeight');
        AssertSamePath(Built, Recorded, '$.data.Lines[0].Length');
        AssertSamePath(Built, Recorded, '$.data.Lines[0].Width');
        AssertSamePath(Built, Recorded, '$.data.Lines[0].Height');
        AssertSamePath(Built, Recorded, '$.data.Lines[0].PkgVol');
        AssertSamePath(Built, Recorded, '$.data.Lines[0].References[0].Kind');
        AssertSamePath(Built, Recorded, '$.data.Lines[0].References[0].Value');
        AssertSamePath(Built, Recorded, '$.data.Lines[0].Pkgs[0].ItemNo');
        AssertSamePath(Built, Recorded, '$.data.References[0].Kind');
        AssertSamePath(Built, Recorded, '$.data.References[0].Value');
        AssertSamePath(Built, Recorded, '$.data.Messages[0].Kind');
        AssertSamePath(Built, Recorded, '$.data.Messages[0].Text');
        AssertSamePath(Built, Recorded, '$.options.Labels');
        AssertSamePath(Built, Recorded, '$.options.Visibility');
        AssertSamePath(Built, Recorded, '$.options.UseShippingRules');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure LabelOptionFollowsFormat()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        Mapper: Codeunit "nShift Ship Shpt. Mapper KBS";
    begin
        LibraryShipment.CreateShipment(ShipmentHeader, ShipmentNoTok);

        Assert.AreEqual('ZPLGK', GetPathText(Mapper.BuildShipmentRequest(ShipmentHeader, "nShift Label Format KBS"::ZPL, true), '$.options.Labels'), 'ZPL sendes som ZPLGK.');
        Assert.AreEqual('none', GetPathText(Mapper.BuildShipmentRequest(ShipmentHeader, "nShift Label Format KBS"::PDF, false), '$.options.Labels'), 'Uten etikett sendes none.');
    end;

    [Test]
    procedure WeightRoundsUpAndVolumeUsesFactor()
    var
        Mapper: Codeunit "nShift Ship Shpt. Mapper KBS";
    begin
        Assert.AreEqual(12001, Mapper.ToShipWeight(12.0001, 1000), 'Vekt rundes opp til hele gram.');
        Assert.AreEqual(12500, Mapper.ToShipWeight(12.5, 1000), 'Hele gram endres ikke.');
        Assert.AreEqual(96000, Mapper.ToShipVolume(0.096, 1000000), 'm³ → cm³.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure BlankCountryUsesCompanyAndPostCodeIsTrimmed()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        Mapper: Codeunit "nShift Ship Shpt. Mapper KBS";
        Built: JsonObject;
    begin
        LibraryShipment.CreateShipment(ShipmentHeader, ShipmentNoTok);
        ShipmentHeader."Ship-to Country/Region Code" := '';
        ShipmentHeader."Ship-to Post Code" := '01 55';
        ShipmentHeader.Modify();

        Built := Mapper.BuildShipmentRequest(ShipmentHeader, "nShift Label Format KBS"::PDF, true);

        Assert.AreEqual('NO', GetPathText(Built, '$.data.Addresses[0].CountryCode'), 'Tomt land betyr firmaets land.');
        Assert.AreEqual('0155', GetPathText(Built, '$.data.Addresses[0].PostCode'), 'Mellomrom fjernes fra postnummer.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure DefaultAddonsAreSentAsServices()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        CarrierAddon: Record "nShift Carrier Addon KBS";
        Mapper: Codeunit "nShift Ship Shpt. Mapper KBS";
        Built: JsonObject;
    begin
        LibraryShipment.CreateShipment(ShipmentHeader, ShipmentNoTok);
        InsertAddon(442010, true);
        InsertAddon(442011, false);

        Built := Mapper.BuildShipmentRequest(ShipmentHeader, "nShift Label Format KBS"::PDF, true);

        Assert.AreEqual('442010', GetPathText(Built, '$.data.Services[0]'), 'Standard tilleggstjeneste skal sendes.');
        Assert.IsFalse(PathExists(Built, '$.data.Services[1]'), 'Tilleggstjenester som ikke er standard skal ikke sendes.');
        CarrierAddon.SetRange("Carrier Service Code", CarrierServiceCodeTok);
        Assert.AreEqual(2, CarrierAddon.Count(), 'Begge tilleggstjenestene finnes.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure ShipmentWithoutPackagesIsRejected()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        Package: Record "nShift Package KBS";
        Mapper: Codeunit "nShift Ship Shpt. Mapper KBS";
    begin
        LibraryShipment.CreateShipment(ShipmentHeader, ShipmentNoTok);
        Package.SetRange("Shipment No.", ShipmentHeader."No.");
        Package.DeleteAll();

        asserterror Mapper.BuildShipmentRequest(ShipmentHeader, "nShift Label Format KBS"::PDF, true);
        Assert.IsTrue(GetLastErrorText().Contains('ingen kolli'), 'Feilen skal forklare at kolli mangler.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure CreateResponseUpdatesShipmentPackagesAndLabels()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        Package: Record "nShift Package KBS";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
        Mapper: Codeunit "nShift Ship Shpt. Mapper KBS";
        Response: JsonObject;
        ErrorText: Text;
    begin
        LibraryShipment.CreateShipment(ShipmentHeader, ShipmentNoTok);
        Response.ReadFrom(NavApp.GetResourceAsText('ship/shipments-pdf.response.json'));

        Assert.IsTrue(Mapper.ApplyCreateResponse(Response, true, ShipmentHeader, TempLabelBuffer, ErrorText), 'Svaret skal godtas: ' + ErrorText);

        Assert.AreEqual(GetPathText(Response, '$.ShpTag'), ShipmentHeader."nShift Shipment Tag", 'ShpTag lagres.');
        Assert.AreEqual(GetPathText(Response, '$.ShpCSID'), Format(ShipmentHeader."nShift ShpCSID", 0, 9), 'ShpCSID lagres.');
        Assert.AreEqual(GetPathText(Response, '$.ShpNo'), ShipmentHeader."Tracking No.", 'Sendingsnr. lagres som sporingsnr.');
        Assert.AreEqual(GetPathText(Response, '$.StackCSID'), Format(ShipmentHeader."nShift Stack ID", 0, 9), 'Stack lagres.');

        Package.Get(ShipmentHeader."No.", 10000);
        Assert.AreEqual(GetPathText(Response, '$.Lines[0].LineTag'), Package."nShift Line Tag", 'LineTag lagres på kolliet.');
        Assert.AreEqual(GetPathText(Response, '$.Lines[0].Pkgs[0].PkgTag'), Package."nShift Package Tag", 'PkgTag lagres på kolliet.');
        Assert.AreEqual(GetPathText(Response, '$.Lines[0].Pkgs[0].PkgNo'), Package."Package Tracking No.", 'Kollinr. lagres.');

        Assert.AreEqual(1, TempLabelBuffer.Count(), 'Én etikett per kolli.');
        TempLabelBuffer.FindFirst();
        Assert.AreEqual("nShift Label Format KBS"::PDF, TempLabelBuffer.Format, 'Type 4 er PDF.');
        Assert.AreEqual(Package."Package Tracking No.", TempLabelBuffer."Package Tracking No.", 'Etiketten kobles til kolliet.');
        Assert.IsTrue(TempLabelBuffer.GetContentBase64().StartsWith('JVBERi0'), 'Innholdet er base64 av en PDF.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure ZplResponseGivesZplLabel()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
        Mapper: Codeunit "nShift Ship Shpt. Mapper KBS";
        Response: JsonObject;
        ErrorText: Text;
    begin
        LibraryShipment.CreateShipment(ShipmentHeader, ShipmentNoTok);
        Response.ReadFrom(NavApp.GetResourceAsText('ship/shipments-zplgk.response.json'));

        Assert.IsTrue(Mapper.ApplyCreateResponse(Response, true, ShipmentHeader, TempLabelBuffer, ErrorText), 'Svaret skal godtas: ' + ErrorText);
        TempLabelBuffer.FindFirst();
        Assert.AreEqual("nShift Label Format KBS"::ZPL, TempLabelBuffer.Format, 'Type 13 er ZPL.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure ReprintResponseGivesLabel()
    var
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
        Mapper: Codeunit "nShift Ship Shpt. Mapper KBS";
        Response: JsonObject;
        ErrorText: Text;
    begin
        Response.ReadFrom(NavApp.GetResourceAsText('ship/labelReprint.response.json'));

        Assert.IsTrue(Mapper.TryReadLabels(Response, ShipmentNoTok, TempLabelBuffer, ErrorText), 'Etiketten skal kunne leses: ' + ErrorText);
        Assert.AreEqual(1, TempLabelBuffer.Count(), 'Én etikett.');
        TempLabelBuffer.FindFirst();
        Assert.AreEqual(GetPathText(Response, '$.Labels[0].PkgNo'), TempLabelBuffer."Package Tracking No.", 'Kollinr. fra etiketten.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure MissingShpTagIsRejected()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
        Mapper: Codeunit "nShift Ship Shpt. Mapper KBS";
        Response: JsonObject;
        ErrorText: Text;
    begin
        LibraryShipment.CreateShipment(ShipmentHeader, ShipmentNoTok);
        Response.ReadFrom('{"Lines":[],"CorrelationID":"c-1"}');

        Assert.IsFalse(Mapper.ApplyCreateResponse(Response, true, ShipmentHeader, TempLabelBuffer, ErrorText), 'Svar uten ShpTag skal avvises.');
        Assert.IsTrue(ErrorText.Contains('ShpTag'), 'Feilen skal nevne ShpTag.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure ErrorsInCreatedResponseKeepShipmentId()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
        Mapper: Codeunit "nShift Ship Shpt. Mapper KBS";
        Response: JsonObject;
        ErrorText: Text;
    begin
        LibraryShipment.CreateShipment(ShipmentHeader, ShipmentNoTok);
        Response.ReadFrom('{"ShpTag":"TAG-1","ShpNo":"123","Lines":[{}],"Errors":[{"message":"Feil-etikett"}]}');

        Assert.IsFalse(Mapper.ApplyCreateResponse(Response, true, ShipmentHeader, TempLabelBuffer, ErrorText), '201 med feil skal avvises.');
        Assert.IsTrue(ErrorText.Contains('Feil-etikett'), 'Feilen fra nShift skal vises.');
        Assert.AreEqual('TAG-1', ShipmentHeader."nShift Shipment Tag", 'ShpTag beholdes så forsendelsen kan slettes i nShift.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure LineCountMismatchIsRejected()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
        Mapper: Codeunit "nShift Ship Shpt. Mapper KBS";
        Response: JsonObject;
        ErrorText: Text;
    begin
        LibraryShipment.CreateShipment(ShipmentHeader, ShipmentNoTok);
        LibraryShipment.InsertPackage(ShipmentHeader."No.", 20000, 5);
        Response.ReadFrom(NavApp.GetResourceAsText('ship/shipments-pdf.response.json'));

        Assert.IsFalse(Mapper.ApplyCreateResponse(Response, true, ShipmentHeader, TempLabelBuffer, ErrorText), 'Feil antall linjer skal avvises.');
        Assert.IsTrue(ErrorText.Contains('2 kolli'), 'Feilen skal vise antall kolli.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure MissingLabelIsRejectedWhenRequired()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
        Mapper: Codeunit "nShift Ship Shpt. Mapper KBS";
        Response: JsonObject;
        ErrorText: Text;
    begin
        LibraryShipment.CreateShipment(ShipmentHeader, ShipmentNoTok);
        Response.ReadFrom(NavApp.GetResourceAsText('ship/shipment-get.response.json'));

        Assert.IsFalse(Mapper.ApplyCreateResponse(Response, true, ShipmentHeader, TempLabelBuffer, ErrorText), 'Uten etikett skal svaret avvises når etikett kreves.');
        Assert.IsTrue(Mapper.ApplyCreateResponse(Response, false, ShipmentHeader, TempLabelBuffer, ErrorText), 'Uten etikett er OK når etikett ikke kreves: ' + ErrorText);
    end;

    [Test]
    procedure LabelFormatIsDetectedFromContent()
    var
        Mapper: Codeunit "nShift Ship Shpt. Mapper KBS";
        LabelFormat: Enum "nShift Label Format KBS";
    begin
        Assert.IsTrue(Mapper.TryDetectLabelFormat('iVBORw0KGgoAAAANSUhEUg', LabelFormat), 'PNG skal gjenkjennes.');
        Assert.AreEqual("nShift Label Format KBS"::PNG, LabelFormat, 'iVBORw0KGgo er PNG.');
        Assert.IsTrue(Mapper.TryDetectLabelFormat('JVBERi0xLjcK', LabelFormat), 'PDF skal gjenkjennes.');
        Assert.AreEqual("nShift Label Format KBS"::PDF, LabelFormat, 'JVBERi0 er PDF.');
        Assert.IsTrue(Mapper.TryDetectLabelFormat('fkRHUjpJTlQ', LabelFormat), 'ZPL skal gjenkjennes.');
        Assert.AreEqual("nShift Label Format KBS"::ZPL, LabelFormat, '~DG er ZPL.');
        Assert.IsFalse(Mapper.TryDetectLabelFormat('R0lGODlh', LabelFormat), 'GIF støttes ikke.');
    end;

    [Test]
    procedure PngLabelTypeIsRead()
    var
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
        Mapper: Codeunit "nShift Ship Shpt. Mapper KBS";
        Response: JsonObject;
        ErrorText: Text;
    begin
        // Type 10 = PNG, verifisert i API-loggen mot nShift 2026-10-21.
        Response.ReadFrom('{"Labels":[{"Content":"iVBORw0KGgoAAAANSUhEUg","Type":10,"PkgNo":"00370730258261057945","Copies":1}]}');

        Assert.IsTrue(Mapper.TryReadLabels(Response, ShipmentNoTok, TempLabelBuffer, ErrorText), 'PNG-etiketten skal leses: ' + ErrorText);
        TempLabelBuffer.FindFirst();
        Assert.AreEqual("nShift Label Format KBS"::PNG, TempLabelBuffer.Format, 'Type 10 er PNG.');
    end;

    [Test]
    procedure PngLabelOptionIsSent()
    var
        Mapper: Codeunit "nShift Ship Shpt. Mapper KBS";
    begin
        Assert.AreEqual('PNG', Mapper.GetLabelsOption("nShift Label Format KBS"::PNG), 'PNG sendes som PNG.');
    end;

    [Test]
    procedure TrackingUrlIsRead()
    var
        Mapper: Codeunit "nShift Ship Shpt. Mapper KBS";
        Response: JsonObject;
    begin
        Response.ReadFrom(NavApp.GetResourceAsText('ship/trackingURL.response.json'));
        Assert.IsTrue(Mapper.GetTrackingUrl(Response).StartsWith('http://sporing.bring.no/'), 'Sporingslenken skal leses.');
    end;

    local procedure InsertAddon(ServiceId: Integer; IsDefault: Boolean)
    var
        CarrierAddon: Record "nShift Carrier Addon KBS";
    begin
        CarrierAddon.Init();
        CarrierAddon."Carrier Service Code" := CarrierServiceCodeTok;
        CarrierAddon."Service ID" := ServiceId;
        CarrierAddon.Default := IsDefault;
        CarrierAddon.Insert();
    end;

    local procedure AssertSamePath(Built: JsonObject; Recorded: JsonObject; Path: Text)
    begin
        Assert.IsTrue(PathExists(Recorded, Path), 'Fixture mangler ' + Path);
        Assert.AreEqual(GetPathText(Recorded, Path), GetPathText(Built, Path), Path);
    end;

    local procedure PathExists(Source: JsonObject; Path: Text): Boolean
    var
        Token: JsonToken;
    begin
        exit(Source.SelectToken(Path, Token));
    end;

    local procedure GetPathText(Source: JsonObject; Path: Text): Text
    var
        Token: JsonToken;
    begin
        if not Source.SelectToken(Path, Token) then
            exit('<mangler>');
        if not Token.IsValue() then
            exit('<ikke verdi>');
        exit(Token.AsValue().AsText());
    end;
}
