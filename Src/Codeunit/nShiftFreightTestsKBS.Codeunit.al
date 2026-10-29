namespace Knowit.nShift.Test;

using Knowit.nShift;
using Microsoft.Finance.GeneralLedger.Account;
using Microsoft.Finance.VAT.Setup;
using Microsoft.Foundation.Shipping;
using Microsoft.Sales.Customer;
using Microsoft.Sales.Receivables;
using Microsoft.Sales.Document;

/// <summary>
/// Tester Fase 4: fraktregel-motoren, fraktlinjen, estimert fraktpris (mot fixtures via HTTP-mock), fraktalternativer,
/// hentesteder, speditørmapping og fraktlinje før bokføring (3.5b).
/// Tester som åpner en dialog etter et nShift-kall gjør Commit og bruker derfor AutoCommit med egne ordrenumre.
/// </summary>
codeunit 73976 "nShift Freight Tests KBS"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "nShift Library Assert KBS";
        LibraryShipment: Codeunit "nShift Library Shipment KBS";
        HttpMock: Codeunit "nShift HTTP Mock KBS";
        FreightRuleMgt: Codeunit "nShift Freight Rule Mgt. KBS";
        FreightLineMgt: Codeunit "nShift Freight Line Mgt. KBS";
        RateMgt: Codeunit "nShift Rate Mgt. KBS";
        LastMessage: Text;
        LookupTargetLineNo: Integer;
        GLAccountNoTok: Label 'NSH-FRAKT', Locked = true;
        CustomerPostingGroupTok: Label 'NSHTEST', Locked = true;
        PriceResponseTok: Label '{"ListPrice":250.0,"Price1":199.0,"Currency":0,"Price2":0.0,"Currency2":0,"StatusCode":0,"StatusMsg":""}', Locked = true;

    // ---------- Fraktregel-motoren (4.3) ----------

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure NoRulesKeepNShiftPrice()
    var
        SalesHeader: Record "Sales Header";
        AppliedRules: Text;
    begin
        InitializeRules(SalesHeader, 'NSH-FR01');
        Assert.AreEqual(200, FreightRuleMgt.ApplyRules(SalesHeader, 'BRING-PAKKE', 1000, 200, AppliedRules), 'Uten regler er prisen uendret.');
        Assert.AreEqual('', AppliedRules, 'Ingen regler brukt.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure CustomerWithFreeFreightPaysNothing()
    var
        SalesHeader: Record "Sales Header";
        FreightRule: Record "nShift Freight Rule KBS";
        AppliedRules: Text;
    begin
        InitializeRules(SalesHeader, 'NSH-FR02');
        InsertRule(1, 'Fraktfritt K10000', FreightRule.Scope::Customer, 'K10000', FreightRule.Action::"Free Freight", 0, 0, false);
        InsertRule(2, 'Fraktfritt annen kunde', FreightRule.Scope::Customer, 'K20000', FreightRule.Action::"Free Freight", 0, 0, false);

        Assert.AreEqual(0, FreightRuleMgt.ApplyRules(SalesHeader, 'BRING-PAKKE', 1000, 200, AppliedRules), 'Fraktfri kunde betaler ingenting.');
        Assert.AreEqual('Fraktfritt K10000', AppliedRules, 'Bare regelen for kunden er brukt.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure SurchargeOnlyAboveOrderAmount()
    var
        SalesHeader: Record "Sales Header";
        FreightRule: Record "nShift Freight Rule KBS";
        AppliedRules: Text;
    begin
        InitializeRules(SalesHeader, 'NSH-FR03');
        InsertRule(1, 'Påslag 10 %', FreightRule.Scope::"All Customers", '', FreightRule.Action::"Percent Surcharge", 10, 1000, false);

        Assert.AreEqual(220, FreightRuleMgt.ApplyRules(SalesHeader, 'BRING-PAKKE', 1500, 200, AppliedRules), 'Over beløpsgrensen gis påslag.');
        Assert.AreEqual(200, FreightRuleMgt.ApplyRules(SalesHeader, 'BRING-PAKKE', 500, 200, AppliedRules), 'Under beløpsgrensen gis ikke påslag.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure RulesApplyInPriorityOrderUntilStop()
    var
        SalesHeader: Record "Sales Header";
        FreightRule: Record "nShift Freight Rule KBS";
        AppliedRules: Text;
    begin
        InitializeRules(SalesHeader, 'NSH-FR04');
        InsertRule(20, 'Påslag 50 %', FreightRule.Scope::"All Customers", '', FreightRule.Action::"Percent Surcharge", 50, 0, false);
        InsertRule(10, 'Fast pris 150', FreightRule.Scope::"All Customers", '', FreightRule.Action::"Fixed Price", 150, 0, true);

        Assert.AreEqual(150, FreightRuleMgt.ApplyRules(SalesHeader, 'BRING-PAKKE', 1000, 200, AppliedRules), 'Laveste prioritet først, og stopp hindrer videre regler.');
        Assert.AreEqual('Fast pris 150', AppliedRules, 'Bare regelen før stopp er brukt.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure RulesAreCumulative()
    var
        SalesHeader: Record "Sales Header";
        FreightRule: Record "nShift Freight Rule KBS";
        AppliedRules: Text;
    begin
        InitializeRules(SalesHeader, 'NSH-FR05');
        InsertRule(1, 'Påslag 10 %', FreightRule.Scope::"All Customers", '', FreightRule.Action::"Percent Surcharge", 10, 0, false);
        InsertRule(2, 'Håndtering 30', FreightRule.Scope::"All Customers", '', FreightRule.Action::"Fixed Surcharge", 30, 0, false);

        Assert.AreEqual(250, FreightRuleMgt.ApplyRules(SalesHeader, 'BRING-PAKKE', 1000, 200, AppliedRules), '200 + 10 % + 30 = 250.');
        Assert.AreEqual('Påslag 10 %; Håndtering 30', AppliedRules, 'Begge reglene listes.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure MinimumAndMaximumPrice()
    var
        SalesHeader: Record "Sales Header";
        FreightRule: Record "nShift Freight Rule KBS";
        AppliedRules: Text;
    begin
        InitializeRules(SalesHeader, 'NSH-FR06');
        InsertRule(1, 'Minstepris 250', FreightRule.Scope::"All Customers", '', FreightRule.Action::"Minimum Price", 250, 0, false);
        Assert.AreEqual(250, FreightRuleMgt.ApplyRules(SalesHeader, 'BRING-PAKKE', 1000, 200, AppliedRules), 'Minstepris løfter prisen.');

        FreightRule.DeleteAll();
        InsertRule(1, 'Makspris 100', FreightRule.Scope::"All Customers", '', FreightRule.Action::"Maximum Price", 100, 0, false);
        Assert.AreEqual(100, FreightRuleMgt.ApplyRules(SalesHeader, 'BRING-PAKKE', 1000, 200, AppliedRules), 'Makspris begrenser prisen.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure ExpiredRuleIsIgnored()
    var
        SalesHeader: Record "Sales Header";
        FreightRule: Record "nShift Freight Rule KBS";
        AppliedRules: Text;
    begin
        InitializeRules(SalesHeader, 'NSH-FR07');
        InsertRule(1, 'Utløpt kampanje', FreightRule.Scope::"All Customers", '', FreightRule.Action::"Free Freight", 0, 0, false);
        FreightRule.FindFirst();
        FreightRule."Ending Date" := SalesHeader."Order Date" - 1;
        FreightRule.Modify();

        Assert.AreEqual(200, FreightRuleMgt.ApplyRules(SalesHeader, 'BRING-PAKKE', 1000, 200, AppliedRules), 'Regel etter sluttdato brukes ikke.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure RuleForOtherServiceOrLocationIsIgnored()
    var
        SalesHeader: Record "Sales Header";
        FreightRule: Record "nShift Freight Rule KBS";
        AppliedRules: Text;
    begin
        InitializeRules(SalesHeader, 'NSH-FR08');
        InsertRule(1, 'Annen tjeneste', FreightRule.Scope::"All Customers", '', FreightRule.Action::"Free Freight", 0, 0, false);
        FreightRule.FindFirst();
        FreightRule."Carrier Service Code" := 'DSV-ANNEN';
        FreightRule.Modify();
        InsertRule(2, 'Annen lokasjon', FreightRule.Scope::"All Customers", '', FreightRule.Action::"Free Freight", 0, 0, false);
        FreightRule.FindLast();
        FreightRule."Location Code" := 'ANNET';
        FreightRule.Modify();

        Assert.AreEqual(200, FreightRuleMgt.ApplyRules(SalesHeader, 'BRING-PAKKE', 1000, 200, AppliedRules), 'Regler for annen tjeneste eller lokasjon brukes ikke.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure BaseAmountExcludesFreightLines()
    var
        SalesHeader: Record "Sales Header";
    begin
        InitializeRules(SalesHeader, 'NSH-FR09');
        AddItemLine(SalesHeader, 10000, 1, 0, 0, 1000);
        AddFreightLineRecord(SalesHeader, 20000, 0, 200);

        Assert.AreEqual(1000, FreightRuleMgt.GetBaseAmountLCY(SalesHeader), 'Fraktlinjer tas ikke med i basisbeløpet.');
    end;

    // ---------- Fraktlinjen (4.7) ----------

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure FreightLineIsCreatedWithPrice()
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
    begin
        InitializeFreight(SalesHeader, 'NSH-FL01');

        FreightLineMgt.UpdateFreightLine(SalesHeader, LibraryShipment.GetCarrierServiceCode(), 199);

        Assert.IsTrue(FreightLineMgt.FindUndeliveredFreightLine(SalesHeader, SalesLine), 'Fraktlinjen skal opprettes.');
        Assert.AreEqual(SalesLine.Type::"G/L Account", SalesLine.Type, 'Linjetype fra oppsettet.');
        Assert.AreEqual(GLAccountNoTok, SalesLine."No.", 'Konto fra oppsettet.');
        Assert.AreEqual(1, SalesLine.Quantity, 'Antall 1.');
        Assert.AreEqual(199, SalesLine."Unit Price", 'Pris etter regler.');
        Assert.AreEqual('Frakt Bring Pakke til bedrift', SalesLine.Description, 'Beskrivelse fra malen «Frakt %1».');
        SalesHeader.Get(SalesHeader."Document Type", SalesHeader."No.");
        Assert.AreEqual(199, SalesHeader."nShift Est. Freight Price KBS", 'Estimert pris lagres på ordren.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure FreightLineIsUpdatedNotDuplicated()
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
    begin
        InitializeFreight(SalesHeader, 'NSH-FL02');

        FreightLineMgt.UpdateFreightLine(SalesHeader, LibraryShipment.GetCarrierServiceCode(), 199);
        FreightLineMgt.UpdateFreightLine(SalesHeader, LibraryShipment.GetCarrierServiceCode(), 150);

        SalesLine.SetRange("Document Type", SalesHeader."Document Type");
        SalesLine.SetRange("Document No.", SalesHeader."No.");
        SalesLine.SetRange("nShift Freight Line KBS", true);
        Assert.AreEqual(1, SalesLine.Count(), 'Én fraktlinje.');
        SalesLine.FindFirst();
        Assert.AreEqual(150, SalesLine."Unit Price", 'Prisen oppdateres.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure DeliveredFreightLineIsNeverTouched()
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
    begin
        InitializeFreight(SalesHeader, 'NSH-FL03');
        AddFreightLineRecord(SalesHeader, 10000, 1, 175);

        FreightLineMgt.UpdateFreightLine(SalesHeader, LibraryShipment.GetCarrierServiceCode(), 199);

        SalesLine.Get(SalesHeader."Document Type", SalesHeader."No.", 10000);
        Assert.AreEqual(175, SalesLine."Unit Price", 'Levert fraktlinje beholder prisen.');
        Assert.IsTrue(FreightLineMgt.FindUndeliveredFreightLine(SalesHeader, SalesLine), 'Ny fraktlinje for neste levering.');
        Assert.AreEqual(199, SalesLine."Unit Price", 'Ny linje får ny pris.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PriceIncludesVatWhenOrderDoes()
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
    begin
        InitializeFreight(SalesHeader, 'NSH-FL04');
        SalesHeader."Prices Including VAT" := true;
        SalesHeader.Modify();

        FreightLineMgt.UpdateFreightLine(SalesHeader, LibraryShipment.GetCarrierServiceCode(), 200);

        FreightLineMgt.FindUndeliveredFreightLine(SalesHeader, SalesLine);
        Assert.AreEqual(250, SalesLine."Unit Price", '200 + 25 % mva. når ordren har priser inkl. mva.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure FreightLineIsPreparedForShipment()
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
    begin
        InitializeFreight(SalesHeader, 'NSH-FL05');
        AddFreightLineRecord(SalesHeader, 10000, 0, 150);
        AddFreightLineRecord(SalesHeader, 20000, 0, 90);
        SalesLine.Get(SalesHeader."Document Type", SalesHeader."No.", 20000);
        SalesLine."Qty. to Ship" := 1;
        SalesLine.Modify();

        FreightLineMgt.PrepareForShipment(SalesHeader, 'NSH000123', LibraryShipment.GetCarrierServiceCode(), 210, true);

        SalesLine.Get(SalesHeader."Document Type", SalesHeader."No.", 10000);
        Assert.AreEqual(1, SalesLine."Qty. to Ship", 'Én fraktlinje leveres med følgeseddelen.');
        Assert.AreEqual(210, SalesLine."Unit Price", 'Med estimert pris fra kolliene.');
        Assert.AreEqual('NSH000123', SalesLine."nShift Shipment No. KBS", 'Fraktlinjen kobles til forsendelsen.');
        SalesLine.Get(SalesHeader."Document Type", SalesHeader."No.", 20000);
        Assert.AreEqual(0, SalesLine."Qty. to Ship", 'Andre uleverte fraktlinjer leveres ikke nå.');
    end;

    // ---------- Fraktpris fra nShift (4.1, 4.2) ----------

    [Test]
    [HandlerFunctions('MessageHandler')]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure CalculateFreightUsesPriceAndRules()
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
        FreightRule: Record "nShift Freight Rule KBS";
    begin
        InitializeFreight(SalesHeader, 'NSH-RT01');
        AddItemLine(SalesHeader, 10000, 5, 2.5, 0.01, 1000);
        InsertRule(1, 'Påslag 10 %', FreightRule.Scope::"All Customers", '', FreightRule.Action::"Percent Surcharge", 10, 0, false);
        HttpMock.EnqueueShipResponse(200, PriceResponseTok);

        Assert.IsTrue(RateMgt.CalculateFreight(SalesHeader), 'Fraktprisen skal beregnes.');

        Assert.IsTrue(HttpMock.GetLastShipUrl().EndsWith('/shipmentPrices'), 'Pris hentes fra /shipmentPrices.');
        Assert.IsTrue(HttpMock.GetLastShipRequestBody().Contains('"PkgWeight":12500'), 'Estimert vekt = 5 × 2,5 kg = 12 500 g: ' + HttpMock.GetLastShipRequestBody());
        Assert.IsTrue(HttpMock.GetLastShipRequestBody().Contains('"PkgVol":50000'), 'Estimert volum = 5 × 0,01 m³ = 50 000 cm³.');
        FreightLineMgt.FindUndeliveredFreightLine(SalesHeader, SalesLine);
        Assert.AreEqual(218.9, SalesLine."Unit Price", '199 + 10 % = 218,90.');
        Assert.IsTrue(LastMessage.Contains('Påslag 10 %'), 'Meldingen viser brukte regler: ' + LastMessage);
        UnbindSubscription(HttpMock);
    end;

    [Test]
    [HandlerFunctions('MessageHandler')]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure MissingPriceWarnsAndKeepsFreightLine()
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
    begin
        InitializeFreight(SalesHeader, 'NSH-RT02');
        AddItemLine(SalesHeader, 10000, 5, 2.5, 0, 1000);
        HttpMock.EnqueueShipResponse(200, NavApp.GetResourceAsText('ship/shipmentPrices.response.json'));

        Assert.IsFalse(RateMgt.CalculateFreight(SalesHeader), 'Uten pris skal fraktlinjen ikke oppdateres.');

        Assert.IsFalse(FreightLineMgt.FindUndeliveredFreightLine(SalesHeader, SalesLine), 'Ingen fraktlinje uten pris.');
        Assert.IsTrue(LastMessage.Contains('Calculation is deactivated'), 'Brukeren får forklaringen fra nShift: ' + LastMessage);
        UnbindSubscription(HttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure OrderWithoutGrossWeightCannotBeEstimated()
    var
        SalesHeader: Record "Sales Header";
    begin
        InitializeFreight(SalesHeader, 'NSH-RT03');
        AddItemLine(SalesHeader, 10000, 5, 0, 0, 1000);

        asserterror RateMgt.CalculateFreight(SalesHeader);
        Assert.IsTrue(GetLastErrorText().Contains('bruttovekt'), 'Feilen skal forklare at bruttovekt mangler: ' + GetLastErrorText());
    end;

    [Test]
    [HandlerFunctions('RateOptionsHandler')]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure RateOptionsFromCheckoutAreMappedAndPriced()
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
        RateOption: Record "nShift Rate Option KBS";
        CarrierService: Record "nShift Carrier Service KBS";
    begin
        InitializeFreight(SalesHeader, 'NSH-RT04');
        AddItemLine(SalesHeader, 10000, 5, 2.5, 0, 1000);
        SalesHeader."nShift Carrier Service KBS" := '';
        SalesHeader.Modify();
        // Bare bibliotekets tjeneste (Bring 3578) skal være kjent – importerte tjenester i sandkassen fjernes (rulles tilbake).
        CarrierService.SetFilter(Code, '<>%1', LibraryShipment.GetCarrierServiceCode());
        CarrierService.DeleteAll();
        HttpMock.EnqueueShipResponse(200, NavApp.GetResourceAsText('ship/checkout.response.json'));
        HttpMock.EnqueueShipResponse(200, PriceResponseTok);
        LookupTargetLineNo := 80000;

        Assert.IsTrue(RateMgt.CalculateFreight(SalesHeader), 'Valgt alternativ skal gi fraktlinje.');

        Assert.IsTrue(HttpMock.GetShipRequest(1).EndsWith('/checkout'), 'Alternativene hentes fra /checkout.');
        RateOption.SetRange("Sales Order No.", SalesHeader."No.");
        Assert.AreEqual(10, RateOption.Count(), 'Alle 10 alternativene lagres.');
        RateOption.SetFilter("Carrier Service Code", '<>%1', '');
        Assert.AreEqual(1, RateOption.Count(), 'Bare produktet som finnes som tjeneste kobles (Bring 3578).');
        RateOption.FindFirst();
        Assert.AreEqual(199, RateOption.Price, 'Pris hentes per kjent alternativ.');
        Assert.IsTrue(RateOption.Selected, 'Valgt alternativ merkes.');
        SalesHeader.Get(SalesHeader."Document Type", SalesHeader."No.");
        Assert.AreEqual(LibraryShipment.GetCarrierServiceCode(), SalesHeader."nShift Carrier Service KBS", 'Tjenesten settes på ordren.');
        FreightLineMgt.FindUndeliveredFreightLine(SalesHeader, SalesLine);
        Assert.AreEqual(199, SalesLine."Unit Price", 'Fraktlinjen får prisen.');
        UnbindSubscription(HttpMock);
    end;

    // ---------- Hentesteder (4.5) ----------

    [Test]
    [HandlerFunctions('ServicePointsHandler')]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure ServicePointIsSelectedFromDropPoints()
    var
        SalesHeader: Record "Sales Header";
        CarrierAddon: Record "nShift Carrier Addon KBS";
        Fixture: JsonObject;
        FirstDropPoint: JsonToken;
    begin
        InitializeFreight(SalesHeader, 'NSH-SP01');
        AddItemLine(SalesHeader, 10000, 5, 2.5, 0, 1000);
        CarrierAddon.Init();
        CarrierAddon."Carrier Service Code" := LibraryShipment.GetCarrierServiceCode();
        CarrierAddon."Service ID" := 442123;
        CarrierAddon.Kind := 12;
        if not CarrierAddon.Insert() then
            CarrierAddon.Modify();
        Fixture.ReadFrom(NavApp.GetResourceAsText('ship/dropPoints.response.json'));
        Fixture.SelectToken('$.DropPoints[0].OriginalID', FirstDropPoint);
        HttpMock.EnqueueShipResponse(200, NavApp.GetResourceAsText('ship/dropPoints.response.json'));

        Assert.IsTrue(RateMgt.SelectServicePoint(SalesHeader), 'Hentested skal velges.');

        Assert.IsTrue(HttpMock.GetLastShipUrl().EndsWith('/dropPoints'), 'Hentesteder hentes fra /dropPoints.');
        Assert.IsTrue(HttpMock.GetLastShipRequestBody().Contains('442123'), 'Hentested-tjenesten (Kind 12) sendes med: ' + HttpMock.GetLastShipRequestBody());
        SalesHeader.Get(SalesHeader."Document Type", SalesHeader."No.");
        Assert.AreEqual(FirstDropPoint.AsValue().AsText(), SalesHeader."nShift Service Point ID KBS", 'OriginalID lagres som hentested-ID.');
        Assert.IsTrue(SalesHeader."nShift Service Point Name KBS" <> '', 'Navnet på hentestedet lagres.');
        UnbindSubscription(HttpMock);
    end;

    // ---------- Speditørmapping (4.8) ----------

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure ShippingAgentFollowsCarrierServiceBothWays()
    var
        SalesHeader: Record "Sales Header";
        CarrierService: Record "nShift Carrier Service KBS";
        ShippingAgent: Record "Shipping Agent";
        ShippingAgentServices: Record "Shipping Agent Services";
    begin
        InitializeFreight(SalesHeader, 'NSH-SA01');
        ShippingAgent.Init();
        ShippingAgent.Code := 'NSHBRING';
        if not ShippingAgent.Insert() then;
        ShippingAgentServices.Init();
        ShippingAgentServices."Shipping Agent Code" := 'NSHBRING';
        ShippingAgentServices.Code := 'PAKKE';
        if not ShippingAgentServices.Insert() then;
        CarrierService.Get(LibraryShipment.GetCarrierServiceCode());
        CarrierService."Shipping Agent Code" := 'NSHBRING';
        CarrierService."Shipping Agent Service Code" := 'PAKKE';
        CarrierService.Modify();

        SalesHeader.Validate("nShift Carrier Service KBS", CarrierService.Code);
        Assert.AreEqual('NSHBRING', SalesHeader."Shipping Agent Code", 'Speditør settes fra tjenesten.');
        Assert.AreEqual('PAKKE', SalesHeader."Shipping Agent Service Code", 'Speditørservice settes fra tjenesten.');

        SalesHeader."nShift Carrier Service KBS" := '';
        SalesHeader.Validate("Shipping Agent Service Code", 'PAKKE');
        Assert.AreEqual(CarrierService.Code, SalesHeader."nShift Carrier Service KBS", 'Tjenesten settes fra speditørservicen.');
    end;

    // ---------- Fraktlinje før bokføring (3.5b) ----------

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure FreightLineIsPricedFromPackagesBeforePosting()
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
        ShipmentHeader: Record "nShift Shipment Header KBS";
        PackageMgt: Codeunit "nShift Package Mgt. KBS";
        PostingSubscribers: Codeunit "nShift Posting Subscribers KBS";
    begin
        InitializeFreight(SalesHeader, 'NSH-PB01');
        AddItemLine(SalesHeader, 10000, 5, 2.5, 0, 1000);
        PackageMgt.GetOrCreateForSalesOrder(SalesHeader, ShipmentHeader);
        PackageMgt.AddPackages(ShipmentHeader, '', 1, 12.5);
        SalesHeader.Get(SalesHeader."Document Type", SalesHeader."No.");
        SalesHeader.Ship := true;
        HttpMock.EnqueueShipResponse(200, PriceResponseTok);

        PostingSubscribers.PrepareFreightLine(SalesHeader);

        Assert.IsTrue(HttpMock.GetLastShipRequestBody().Contains('"PkgWeight":12500'), 'Prisen hentes for de registrerte kolliene.');
        Assert.IsTrue(FreightLineMgt.FindUndeliveredFreightLine(SalesHeader, SalesLine), 'Fraktlinje skal finnes.');
        Assert.AreEqual(199, SalesLine."Unit Price", 'Pris fra registrerte kolli.');
        Assert.AreEqual(1, SalesLine."Qty. to Ship", 'Fraktlinjen leveres med følgeseddelen.');
        Assert.AreEqual(ShipmentHeader."No.", SalesLine."nShift Shipment No. KBS", 'Fraktlinjen kobles til forsendelsen.');
        UnbindSubscription(HttpMock);
    end;

    // ---------- Endelig fraktpris (4b) ----------

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure FinalPriceReplacesEstimateOnDeliveredLine()
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
        ShipmentHeader: Record "nShift Shipment Header KBS";
        FinalPriceMgt: Codeunit "nShift Final Price Mgt. KBS";
        ResultText: Text;
    begin
        InitializeFreight(SalesHeader, 'NSH-FP01');
        CreateCreatedShipment(ShipmentHeader, 'NSH-FPS1', SalesHeader."No.");
        AddFreightLineRecord(SalesHeader, 20000, 1, 150);
        LinkFreightLine(SalesHeader, 20000, ShipmentHeader."No.", 0);
        HttpMock.EnqueueShipResponse(200, PriceResponseTok);

        Assert.IsTrue(FinalPriceMgt.UpdateFinalPrice(ShipmentHeader, ResultText), 'Endelig pris skal settes: ' + ResultText);

        SalesLine.Get(SalesHeader."Document Type", SalesHeader."No.", 20000);
        Assert.AreEqual(199, SalesLine."Unit Price", 'Estimatet (150) erstattes av endelig pris (199).');
        ShipmentHeader.Get(ShipmentHeader."No.");
        Assert.AreEqual(199, ShipmentHeader."nShift Freight Price", 'nShift-prisen lagres på forsendelsen.');
        Assert.AreEqual(199, ShipmentHeader."Final Freight Price", 'Endelig pris lagres på forsendelsen.');
        Assert.IsTrue(ShipmentHeader."Price Updated on Order", 'Forsendelsen merkes som oppdatert.');
        UnbindSubscription(HttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure FinalPriceUsesFreightRules()
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
        ShipmentHeader: Record "nShift Shipment Header KBS";
        FreightRule: Record "nShift Freight Rule KBS";
        FinalPriceMgt: Codeunit "nShift Final Price Mgt. KBS";
        ResultText: Text;
    begin
        InitializeFreight(SalesHeader, 'NSH-FP02');
        InsertRule(1, 'Fraktfritt K10000', FreightRule.Scope::Customer, 'K10000', FreightRule.Action::"Free Freight", 0, 0, false);
        CreateCreatedShipment(ShipmentHeader, 'NSH-FPS2', SalesHeader."No.");
        AddFreightLineRecord(SalesHeader, 20000, 1, 150);
        LinkFreightLine(SalesHeader, 20000, ShipmentHeader."No.", 0);
        HttpMock.EnqueueShipResponse(200, PriceResponseTok);

        Assert.IsTrue(FinalPriceMgt.UpdateFinalPrice(ShipmentHeader, ResultText), 'Endelig pris skal settes: ' + ResultText);

        SalesLine.Get(SalesHeader."Document Type", SalesHeader."No.", 20000);
        Assert.AreEqual(0, SalesLine."Unit Price", 'Fraktfri kunde betaler ingenting, også for endelig pris.');
        ShipmentHeader.Get(ShipmentHeader."No.");
        Assert.AreEqual('Fraktfritt K10000', ShipmentHeader."Applied Freight Rules", 'Brukte regler lagres på forsendelsen.');
        UnbindSubscription(HttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PartialDeliveriesUpdateOwnFreightLine()
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
        FirstShipment: Record "nShift Shipment Header KBS";
        SecondShipment: Record "nShift Shipment Header KBS";
        FinalPriceMgt: Codeunit "nShift Final Price Mgt. KBS";
        ResultText: Text;
    begin
        InitializeFreight(SalesHeader, 'NSH-FP03');
        CreateCreatedShipment(FirstShipment, 'NSH-FPS3A', SalesHeader."No.");
        CreateCreatedShipment(SecondShipment, 'NSH-FPS3B', SalesHeader."No.");
        AddFreightLineRecord(SalesHeader, 20000, 1, 111);
        LinkFreightLine(SalesHeader, 20000, FirstShipment."No.", 0);
        AddFreightLineRecord(SalesHeader, 30000, 1, 150);
        LinkFreightLine(SalesHeader, 30000, SecondShipment."No.", 0);
        HttpMock.EnqueueShipResponse(200, PriceResponseTok);

        Assert.IsTrue(FinalPriceMgt.UpdateFinalPrice(SecondShipment, ResultText), 'Endelig pris skal settes: ' + ResultText);

        SalesLine.Get(SalesHeader."Document Type", SalesHeader."No.", 30000);
        Assert.AreEqual(199, SalesLine."Unit Price", 'Fraktlinjen for andre delleveranse oppdateres.');
        SalesLine.Get(SalesHeader."Document Type", SalesHeader."No.", 20000);
        Assert.AreEqual(111, SalesLine."Unit Price", 'Fraktlinjen for første delleveranse røres ikke.');
        UnbindSubscription(HttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure InvoicedFreightLineIsNotChanged()
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
        ShipmentHeader: Record "nShift Shipment Header KBS";
        FinalPriceMgt: Codeunit "nShift Final Price Mgt. KBS";
        ResultText: Text;
    begin
        InitializeFreight(SalesHeader, 'NSH-FP04');
        CreateCreatedShipment(ShipmentHeader, 'NSH-FPS4', SalesHeader."No.");
        AddFreightLineRecord(SalesHeader, 20000, 1, 150);
        LinkFreightLine(SalesHeader, 20000, ShipmentHeader."No.", 1);
        HttpMock.EnqueueShipResponse(200, PriceResponseTok);

        Assert.IsFalse(FinalPriceMgt.UpdateFinalPrice(ShipmentHeader, ResultText), 'Fakturert linje skal ikke endres.');

        SalesLine.Get(SalesHeader."Document Type", SalesHeader."No.", 20000);
        Assert.AreEqual(150, SalesLine."Unit Price", 'Prisen på fakturert linje er uendret.');
        ShipmentHeader.Get(ShipmentHeader."No.");
        Assert.IsTrue(ShipmentHeader."Last Error Text".Contains('fakturert'), 'Årsaken vises på forsendelsen: ' + ShipmentHeader."Last Error Text");
        Assert.AreEqual(199, ShipmentHeader."Final Freight Price", 'Endelig pris lagres likevel på forsendelsen.');
        Assert.IsFalse(ShipmentHeader."Price Updated on Order", 'Ikke merket som oppdatert.');
        UnbindSubscription(HttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure DeletedOrderIsReportedOnShipment()
    var
        SalesHeader: Record "Sales Header";
        ShipmentHeader: Record "nShift Shipment Header KBS";
        FinalPriceMgt: Codeunit "nShift Final Price Mgt. KBS";
        ResultText: Text;
    begin
        InitializeFreight(SalesHeader, 'NSH-FP05');
        CreateCreatedShipment(ShipmentHeader, 'NSH-FPS5', 'NSH-SLETTET');
        HttpMock.EnqueueShipResponse(200, PriceResponseTok);

        Assert.IsFalse(FinalPriceMgt.UpdateFinalPrice(ShipmentHeader, ResultText), 'Uten ordre kan ikke fraktlinjen oppdateres.');
        ShipmentHeader.Get(ShipmentHeader."No.");
        Assert.IsTrue(ShipmentHeader."Last Error Text".Contains('finnes ikke'), 'Årsaken vises på forsendelsen: ' + ShipmentHeader."Last Error Text");
        Assert.AreEqual(199, ShipmentHeader."nShift Freight Price", 'nShift-prisen lagres likevel.');
        UnbindSubscription(HttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure MissingFinalPriceKeepsEstimate()
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
        ShipmentHeader: Record "nShift Shipment Header KBS";
        FinalPriceMgt: Codeunit "nShift Final Price Mgt. KBS";
        ResultText: Text;
    begin
        InitializeFreight(SalesHeader, 'NSH-FP06');
        CreateCreatedShipment(ShipmentHeader, 'NSH-FPS6', SalesHeader."No.");
        AddFreightLineRecord(SalesHeader, 20000, 1, 150);
        LinkFreightLine(SalesHeader, 20000, ShipmentHeader."No.", 0);
        HttpMock.EnqueueShipResponse(200, NavApp.GetResourceAsText('ship/shipmentPrices.response.json'));

        Assert.IsFalse(FinalPriceMgt.UpdateFinalPrice(ShipmentHeader, ResultText), 'Uten pris fra nShift oppdateres ikke linjen.');

        SalesLine.Get(SalesHeader."Document Type", SalesHeader."No.", 20000);
        Assert.AreEqual(150, SalesLine."Unit Price", 'Estimatet beholdes.');
        ShipmentHeader.Get(ShipmentHeader."No.");
        Assert.IsTrue(ShipmentHeader."Last Error Text".Contains('Calculation is deactivated'), 'Forklaringen fra nShift lagres: ' + ShipmentHeader."Last Error Text");
        Assert.AreEqual(ShipmentHeader.Status::Created, ShipmentHeader.Status, 'Status endres ikke av manglende pris.');
        UnbindSubscription(HttpMock);
    end;

    // ---------- Hjelpere ----------

    /// <summary>
    /// Forsendelse med kolli og status Opprettet for salgsordren – slik den står etter opprettelse i nShift.
    /// </summary>
    local procedure CreateCreatedShipment(var ShipmentHeader: Record "nShift Shipment Header KBS"; ShipmentNo: Code[20]; SalesOrderNo: Code[20])
    begin
        LibraryShipment.CreateShipment(ShipmentHeader, ShipmentNo);
        ShipmentHeader."Sales Order No." := SalesOrderNo;
        ShipmentHeader.Status := ShipmentHeader.Status::Created;
        ShipmentHeader."nShift Shipment Tag" := 'TAG-' + ShipmentNo;
        ShipmentHeader.Modify();
    end;

    local procedure LinkFreightLine(SalesHeader: Record "Sales Header"; LineNo: Integer; ShipmentNo: Code[20]; QtyInvoiced: Decimal)
    var
        SalesLine: Record "Sales Line";
    begin
        SalesLine.Get(SalesHeader."Document Type", SalesHeader."No.", LineNo);
        SalesLine."nShift Shipment No. KBS" := ShipmentNo;
        SalesLine."Quantity Invoiced" := QtyInvoiced;
        SalesLine.Modify();
    end;

    [MessageHandler]
    procedure MessageHandler(Message: Text[1024])
    begin
        LastMessage := Message;
    end;

    [ModalPageHandler]
    procedure RateOptionsHandler(var RateOptions: TestPage "nShift Rate Options KBS")
    var
        RateOption: Record "nShift Rate Option KBS";
    begin
        RateOption.SetRange("Line No.", LookupTargetLineNo);
        RateOption.FindFirst();
        RateOptions.GoToRecord(RateOption);
        RateOptions.OK().Invoke();
    end;

    [ModalPageHandler]
    procedure ServicePointsHandler(var ServicePoints: TestPage "nShift Service Points KBS")
    begin
        ServicePoints.First();
        ServicePoints.OK().Invoke();
    end;

    local procedure InitializeRules(var SalesHeader: Record "Sales Header"; OrderNo: Code[20])
    var
        FreightRule: Record "nShift Freight Rule KBS";
    begin
        FreightRule.DeleteAll();
        CreateSalesOrder(SalesHeader, OrderNo);
    end;

    local procedure InitializeFreight(var SalesHeader: Record "Sales Header"; OrderNo: Code[20])
    var
        Setup: Record "nShift Setup KBS";
        GLAccount: Record "G/L Account";
        VATPostingSetup: Record "VAT Posting Setup";
        FreightRule: Record "nShift Freight Rule KBS";
        ShipmentHeader: Record "nShift Shipment Header KBS";
        Customer: Record Customer;
    begin
        LastMessage := '';
        if not Customer.Get('K10000') then begin
            Customer.Init();
            Customer."No." := 'K10000';
            Customer.Name := 'Testkunde AS';
            Customer.Insert();
        end;
        Clear(HttpMock);
        LibraryShipment.InitializeHttpMock(HttpMock);
        if not ShipmentHeader.Get('NSH-FRTLIB') then
            LibraryShipment.CreateShipment(ShipmentHeader, 'NSH-FRTLIB');
        FreightRule.DeleteAll();

        if not VATPostingSetup.Get('', '') then begin
            VATPostingSetup.Init();
            VATPostingSetup.Insert();
        end;
        VATPostingSetup."VAT Calculation Type" := VATPostingSetup."VAT Calculation Type"::"Normal VAT";
        VATPostingSetup."VAT %" := 25;
        VATPostingSetup.Modify();
        if not GLAccount.Get(GLAccountNoTok) then begin
            GLAccount.Init();
            GLAccount."No." := GLAccountNoTok;
            GLAccount.Name := 'Frakt';
            GLAccount.Insert();
        end;
        GLAccount."Account Type" := GLAccount."Account Type"::Posting;
        GLAccount."Direct Posting" := true;
        GLAccount.Blocked := false;
        GLAccount."Gen. Prod. Posting Group" := '';
        GLAccount."VAT Prod. Posting Group" := '';
        GLAccount.Modify();

        Setup.Get();
        Setup."Freight Line Type" := Setup."Freight Line Type"::"G/L Account";
        Setup."Freight Line No." := GLAccountNoTok;
        Setup."Freight Line Description" := 'Frakt %1';
        Setup.Modify();
        CreateSalesOrder(SalesHeader, OrderNo);
    end;

    local procedure CreateSalesOrder(var SalesHeader: Record "Sales Header"; OrderNo: Code[20])
    var
        CustomerPostingGroup: Record "Customer Posting Group";
    begin
        // Ekte ordrer får bokføringsgruppe fra kunden; Sales Line slår den opp når en finanslinje opprettes.
        if not CustomerPostingGroup.Get(CustomerPostingGroupTok) then begin
            CustomerPostingGroup.Init();
            CustomerPostingGroup.Code := CustomerPostingGroupTok;
            CustomerPostingGroup.Insert();
        end;
        SalesHeader.Init();
        SalesHeader."Customer Posting Group" := CustomerPostingGroupTok;
        SalesHeader."Document Type" := SalesHeader."Document Type"::Order;
        SalesHeader."No." := OrderNo;
        SalesHeader."Sell-to Customer No." := 'K10000';
        SalesHeader."Order Date" := WorkDate();
        SalesHeader."Posting Date" := WorkDate();
        SalesHeader."Ship-to Name" := 'Testkunde AS';
        SalesHeader."Ship-to Address" := 'Storgata 1';
        SalesHeader."Ship-to Post Code" := '0155';
        SalesHeader."Ship-to City" := 'OSLO';
        SalesHeader."Ship-to Country/Region Code" := 'NO';
        SalesHeader."Location Code" := 'NSH-TEST';
        SalesHeader."nShift Carrier Service KBS" := 'BRING-PAKKE';
        SalesHeader.Insert();
    end;

    local procedure AddItemLine(SalesHeader: Record "Sales Header"; LineNo: Integer; Qty: Decimal; GrossWeight: Decimal; UnitVolume: Decimal; LineAmount: Decimal)
    var
        SalesLine: Record "Sales Line";
    begin
        SalesLine.Init();
        SalesLine."Document Type" := SalesHeader."Document Type";
        SalesLine."Document No." := SalesHeader."No.";
        SalesLine."Line No." := LineNo;
        SalesLine.Type := SalesLine.Type::Item;
        SalesLine.Quantity := Qty;
        SalesLine."Outstanding Quantity" := Qty;
        SalesLine."Gross Weight" := GrossWeight;
        SalesLine."Unit Volume" := UnitVolume;
        SalesLine.Amount := LineAmount;
        SalesLine.Insert();
    end;

    local procedure AddFreightLineRecord(SalesHeader: Record "Sales Header"; LineNo: Integer; QtyShipped: Decimal; UnitPrice: Decimal)
    var
        SalesLine: Record "Sales Line";
    begin
        SalesLine.Init();
        SalesLine."Document Type" := SalesHeader."Document Type";
        SalesLine."Document No." := SalesHeader."No.";
        SalesLine."Line No." := LineNo;
        SalesLine.Type := SalesLine.Type::"G/L Account";
        SalesLine."No." := GLAccountNoTok;
        SalesLine.Quantity := 1;
        SalesLine."Quantity Shipped" := QtyShipped;
        SalesLine."Outstanding Quantity" := 1 - QtyShipped;
        SalesLine."Unit Price" := UnitPrice;
        SalesLine.Amount := UnitPrice;
        SalesLine."nShift Freight Line KBS" := true;
        SalesLine.Insert();
    end;

    local procedure InsertRule(NewPriority: Integer; NewDescription: Text[100]; NewScope: Enum "nShift Freight Rule Scope KBS"; NewScopeCode: Code[20]; NewAction: Enum "nShift Freight Rule Action KBS"; NewValue: Decimal; MinimumOrderAmount: Decimal; StopFurtherRules: Boolean)
    var
        FreightRule: Record "nShift Freight Rule KBS";
    begin
        FreightRule.Init();
        FreightRule.Priority := NewPriority;
        FreightRule.Description := NewDescription;
        FreightRule.Scope := NewScope;
        FreightRule."Scope Code" := NewScopeCode;
        FreightRule.Action := NewAction;
        FreightRule.Value := NewValue;
        FreightRule."Minimum Order Amount" := MinimumOrderAmount;
        FreightRule."Stop Further Rules" := StopFurtherRules;
        FreightRule.Insert();
    end;
}
