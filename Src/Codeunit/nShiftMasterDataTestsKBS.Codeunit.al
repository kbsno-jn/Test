namespace Knowit.nShift.Test;

using Knowit.nShift;

/// <summary>
/// Tester import av masterdata (2.8) mot products/stacks/senderAddress tatt opp fra Actor 13131:
/// 14 produkter (DSV 5, H.R Olsen 3, Fraktbrev 1, Bring 5), én stack per undertransportør.
/// </summary>
codeunit 73974 "nShift Master Data Tests KBS"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "nShift Library Assert KBS";
        LibraryShipment: Codeunit "nShift Library Shipment KBS";
        HttpMock: Codeunit "nShift HTTP Mock KBS";
        ShipmentMgt: Codeunit "nShift Shipment Mgt. KBS";

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure ImportCreatesServicesAddonsAndGoodsTypes()
    var
        CarrierService: Record "nShift Carrier Service KBS";
        CarrierAddon: Record "nShift Carrier Addon KBS";
        GoodsType: Record "nShift Goods Type KBS";
    begin
        Initialize();
        EnqueueMasterData();

        Assert.AreEqual(14, ShipmentMgt.ImportMasterData(), 'Alle 14 produktene skal leses.');

        Assert.AreEqual(14, CarrierService.Count(), 'Én tjeneste per produkt.');
        CarrierService.Get('BRING-5299');
        Assert.AreEqual(3578, CarrierService."Prod Concept ID", 'ProdConceptID lagres.');
        Assert.AreEqual(5299, CarrierService."Prod CSID", 'ProdCSID lagres.');
        Assert.AreEqual(1273, CarrierService."Subcarrier CSID", 'SubcarrierCSID lagres.');
        Assert.AreEqual('BRING', CarrierService."Carrier Code", 'Transportørkode lages av navnet.');
        Assert.AreEqual('Bring – Pakke til bedrift', CarrierService.Description, 'Beskrivelse = transportør – produkt.');
        Assert.AreEqual(113117, CarrierService."Default Stack ID", 'Stack hentes fra /stacks via SubcarrierCSID.');

        CarrierService.Get('HROLSEN-9475');
        Assert.AreEqual(0, CarrierService."Prod Concept ID", 'Egendefinert transportør har ikke ProdConceptID.');
        Assert.AreEqual(9475, CarrierService."Prod CSID", 'Men ProdCSID er satt.');

        CarrierAddon.SetRange("Carrier Service Code", 'BRING-5299');
        Assert.AreEqual(10, CarrierAddon.Count(), 'Tilleggstjenestene for produktet skal importeres.');
        CarrierAddon.Get('BRING-5299', 442010);
        Assert.AreEqual('Elektronisk varsling til tredjepart', CarrierAddon.Description, 'Navnet på tilleggstjenesten lagres.');

        Assert.IsTrue(GoodsType.Get(101), 'Godstype 101 skal importeres.');
        Assert.AreEqual('CLL', GoodsType.Code, 'Godstypekoden lagres.');
        Assert.AreEqual('Colli', GoodsType.Description, 'Godstypenavnet lagres.');
        UnbindSubscription(HttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure ReimportKeepsUserMaintainedFields()
    var
        CarrierService: Record "nShift Carrier Service KBS";
        CarrierAddon: Record "nShift Carrier Addon KBS";
    begin
        Initialize();
        EnqueueMasterData();
        ShipmentMgt.ImportMasterData();
        CarrierService.Get('BRING-5299');
        CarrierService.Description := 'Bring bedrift (egen tekst)';
        CarrierService.Blocked := true;
        CarrierService."Max Weight (kg)" := 35;
        CarrierService."Default Stack ID" := 999;
        CarrierService.Modify();
        CarrierAddon.Get('BRING-5299', 442010);
        CarrierAddon.Default := true;
        CarrierAddon.Modify();

        EnqueueMasterData();
        ShipmentMgt.ImportMasterData();

        Assert.AreEqual(14, CarrierService.Count(), 'Ny import skal ikke lage duplikater.');
        CarrierService.Get('BRING-5299');
        Assert.AreEqual('Bring bedrift (egen tekst)', CarrierService.Description, 'Egen beskrivelse beholdes.');
        Assert.IsTrue(CarrierService.Blocked, 'Sperret beholdes.');
        Assert.AreEqual(35, CarrierService."Max Weight (kg)", 'Maks. vekt beholdes.');
        Assert.AreEqual(999, CarrierService."Default Stack ID", 'Valgt stack beholdes.');
        CarrierAddon.Get('BRING-5299', 442010);
        Assert.IsTrue(CarrierAddon.Default, 'Standard tilleggstjeneste beholdes.');
        UnbindSubscription(HttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure ManuallyCreatedServiceIsAdopted()
    var
        CarrierService: Record "nShift Carrier Service KBS";
    begin
        Initialize();
        CarrierService.Init();
        CarrierService.Code := 'BRING-PAKKE';
        CarrierService.Description := 'Bring Pakke til bedrift';
        CarrierService."Prod Concept ID" := 3578;
        CarrierService.Insert();
        EnqueueMasterData();

        ShipmentMgt.ImportMasterData();

        CarrierService.Get('BRING-PAKKE');
        Assert.AreEqual(5299, CarrierService."Prod CSID", 'Manuell tjeneste med samme ProdConceptID skal kobles til produktet.');
        Assert.IsFalse(CarrierService.Get('BRING-5299'), 'Det skal ikke lages en ekstra tjeneste for samme produkt.');
        Assert.AreEqual(14, CarrierService.Count(), 'Fortsatt én tjeneste per produkt.');
        UnbindSubscription(HttpMock);
    end;

    [Test]
    procedure CarrierCodeIsMadeFromName()
    var
        MasterMapper: Codeunit "nShift Ship Master Mapper KBS";
    begin
        Assert.AreEqual('HROLSEN', MasterMapper.GetCarrierCode('H.R Olsen'), 'Punktum og mellomrom fjernes.');
        Assert.AreEqual('DSVNORGE', MasterMapper.GetCarrierCode('DSV Norge'), 'Store bokstaver.');
        Assert.AreEqual('ABCDEFGHIJ', MasterMapper.GetCarrierCode('abcdefghijklmn'), 'Maks. 10 tegn.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure SenderAddressIsReadFromNShift()
    var
        LocationSetup: Record "nShift Location Setup KBS";
        ShipmentHeader: Record "nShift Shipment Header KBS";
    begin
        Initialize();
        LibraryShipment.CreateShipment(ShipmentHeader, 'NSH-MD1');
        LocationSetup.Get(ShipmentHeader."Location Code");
        HttpMock.EnqueueShipResponse(200, NavApp.GetResourceAsText('ship/senderAddress.response.json'));

        ShipmentMgt.GetSenderAddress(LocationSetup);

        LocationSetup.Get(LocationSetup."Location Code");
        Assert.AreEqual('Saferoad B.Berntsen AS', LocationSetup."Sender Name", 'Avsendernavnet hentes fra nShift.');
        Assert.AreEqual('Hensmoveien 43', LocationSetup."Sender Address", 'Adressen hentes fra nShift.');
        Assert.AreEqual('3516', LocationSetup."Sender Post Code", 'Postnummeret hentes fra nShift.');
        Assert.AreEqual('NO', LocationSetup."Sender Country/Region Code", 'ISO-landkoden oversettes til BC-landkode.');
        Assert.IsTrue(HttpMock.GetLastShipUrl().EndsWith('/senderAddress'), 'Avsenderen hentes fra /senderAddress.');
        UnbindSubscription(HttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure FailedImportShowsError()
    begin
        Initialize();
        HttpMock.EnqueueShipResponse(404, '{"ErrorType":"Not Found","Message":"Cannot find actor with ID 13131","Errors":[]}');

        asserterror ShipmentMgt.ImportMasterData();
        Assert.IsTrue(GetLastErrorText().Contains('Cannot find actor'), 'Feilen fra nShift skal vises: ' + GetLastErrorText());
    end;

    local procedure Initialize()
    var
        CarrierService: Record "nShift Carrier Service KBS";
        CarrierAddon: Record "nShift Carrier Addon KBS";
        GoodsType: Record "nShift Goods Type KBS";
    begin
        Clear(HttpMock);
        LibraryShipment.InitializeHttpMock(HttpMock);
        CarrierAddon.DeleteAll();
        CarrierService.DeleteAll();
        GoodsType.DeleteAll();
    end;

    local procedure EnqueueMasterData()
    begin
        HttpMock.EnqueueShipResponse(200, NavApp.GetResourceAsText('ship/products.response.json'));
        HttpMock.EnqueueShipResponse(200, NavApp.GetResourceAsText('ship/stacks.response.json'));
    end;
}
