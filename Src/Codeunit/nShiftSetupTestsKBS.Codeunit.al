namespace Knowit.nShift.Test;

using Knowit.nShift;
using Microsoft.Foundation.NoSeries;
using Microsoft.Inventory.Location;
using Microsoft.Sales.Document;

codeunit 73964 "nShift Setup Tests KBS"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "nShift Library Assert KBS";
        TestUserTok: Label 'NSHIFT-TESTUSER', Locked = true;
        TestSecretKeyTok: Label 'nShiftKBS-UnitTestSecret', Locked = true;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure InstallInsertsDefaults()
    var
        Setup: Record "nShift Setup KBS";
        NoSeries: Record "No. Series";
        PackageType: Record "nShift Package Type KBS";
        Install: Codeunit "nShift Install KBS";
    begin
        Setup.DeleteAll();
        Install.InsertDefaults();

        Setup.Get();
        Assert.AreEqual('https://restapi.shipmentserver.com', Setup."Base URL", 'Base-URL skal være prod-serveren (også for test-Actorer).');
        Assert.AreEqual('https://account.nshiftportal.com/idp/connect/token', Setup."Token URL", 'Token-URL skal fylles inn.');
        Assert.AreEqual('https://api.printnode.com', Setup."PrintNode Base URL", 'PrintNode-URL skal fylles inn.');
        Assert.AreEqual(1000, Setup."Weight Factor", 'Vektfaktor kg → g.');
        Assert.AreEqual(1000000, Setup."Volume Factor", 'Volumfaktor m³ → cm³.');
        Assert.AreEqual(30000, Setup."Request Timeout (ms)", 'Standard tidsavbrudd 30 s.');
        Assert.IsTrue(NoSeries.Get(Setup."Shipment Nos."), 'Nummerserien skal opprettes.');
        Assert.IsTrue(PackageType.Get('ESKE'), 'Kollitypen ESKE skal opprettes.');
        Assert.IsTrue(PackageType.Get('PALL'), 'Kollitypen PALL skal opprettes.');
        Assert.AreEqual('ESKE', Setup."Default Package Type Code", 'ESKE skal være standard kollitype.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure InstallKeepsExistingValues()
    var
        Setup: Record "nShift Setup KBS";
        Install: Codeunit "nShift Install KBS";
    begin
        Install.InsertDefaults();
        Setup.Get();
        Setup."Weight Factor" := 1;
        Setup."Base URL" := 'https://example.test';
        Setup.Modify();

        Install.InsertDefaults();

        Setup.Get();
        Assert.AreEqual(1, Setup."Weight Factor", 'Eksisterende vektfaktor skal beholdes.');
        Assert.AreEqual('https://example.test', Setup."Base URL", 'Eksisterende URL skal beholdes.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure BaseUrlIsSameForBothEnvironments()
    var
        Setup: Record "nShift Setup KBS";
    begin
        Setup.GetRecordOnce();
        Setup."Base URL" := 'https://ship.example/';
        Setup.Environment := Setup.Environment::Test;
        Assert.AreEqual('https://ship.example', Setup.GetBaseUrl(), 'Base-URL uten avsluttende skråstrek.');
        Setup.Environment := Setup.Environment::Production;
        Assert.AreEqual('https://ship.example', Setup.GetBaseUrl(), 'Miljøet skal ikke endre base-URL.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure FreightLineTypeRejectsUnsupportedTypes()
    var
        Setup: Record "nShift Setup KBS";
    begin
        Setup.GetRecordOnce();
        Setup.Validate("Freight Line Type", "Sales Line Type"::"G/L Account");
        asserterror Setup.Validate("Freight Line Type", "Sales Line Type"::"Fixed Asset");
        Assert.IsTrue(StrPos(GetLastErrorText(), 'Fraktlinjetypen') > 0, 'Anleggsmiddel skal avvises som fraktlinjetype.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PackingStationResolutionOrder()
    var
        PackingStation: Record "nShift Packing Station KBS";
        UserSetup: Record "nShift User Setup KBS";
        LocationSetup: Record "nShift Location Setup KBS";
        Setup: Record "nShift Setup KBS";
        PackStationMgt: Codeunit "nShift Pack. Station Mgt. KBS";
        LocationCode: Code[10];
    begin
        LocationCode := CreateLocation();
        InsertPackingStation('PS-DOC', false);
        InsertPackingStation('PS-USER', false);
        InsertPackingStation('PS-LOC', false);
        InsertPackingStation('PS-SETUP', false);

        Setup.GetRecordOnce();
        Setup."Default Packing Station Code" := 'PS-SETUP';
        Setup.Modify();
        LocationSetup.Init();
        LocationSetup."Location Code" := LocationCode;
        LocationSetup."Default Packing Station Code" := 'PS-LOC';
        LocationSetup.Insert();
        UserSetup.Init();
        UserSetup."User ID" := TestUserTok;
        UserSetup."Packing Station Code" := 'PS-USER';
        UserSetup.Insert();

        PackStationMgt.ResolvePackingStation('PS-DOC', LocationCode, TestUserTok, PackingStation);
        Assert.AreEqual('PS-DOC', PackingStation.Code, 'Dokumentets pakkebord skal vinne.');

        PackStationMgt.ResolvePackingStation('', LocationCode, TestUserTok, PackingStation);
        Assert.AreEqual('PS-USER', PackingStation.Code, 'Brukerens pakkebord skal brukes når dokumentet ikke har pakkebord.');

        PackStationMgt.ResolvePackingStation('', LocationCode, 'ANNEN-BRUKER', PackingStation);
        Assert.AreEqual('PS-LOC', PackingStation.Code, 'Lokasjonens pakkebord skal brukes når brukeren ikke har pakkebord.');

        PackStationMgt.ResolvePackingStation('', '', 'ANNEN-BRUKER', PackingStation);
        Assert.AreEqual('PS-SETUP', PackingStation.Code, 'Oppsettets pakkebord skal brukes til slutt.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure BlockedPackingStationIsSkipped()
    var
        PackingStation: Record "nShift Packing Station KBS";
        Setup: Record "nShift Setup KBS";
        PackStationMgt: Codeunit "nShift Pack. Station Mgt. KBS";
    begin
        InsertPackingStation('PS-BLOCKED', true);
        InsertPackingStation('PS-SETUP', false);
        Setup.GetRecordOnce();
        Setup."Default Packing Station Code" := 'PS-SETUP';
        Setup.Modify();

        PackStationMgt.ResolvePackingStation('PS-BLOCKED', '', 'ANNEN-BRUKER', PackingStation);
        Assert.AreEqual('PS-SETUP', PackingStation.Code, 'Sperret pakkebord skal hoppes over.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure MissingPackingStationGivesError()
    var
        PackingStation: Record "nShift Packing Station KBS";
        Setup: Record "nShift Setup KBS";
        PackStationMgt: Codeunit "nShift Pack. Station Mgt. KBS";
    begin
        Setup.GetRecordOnce();
        Setup."Default Packing Station Code" := '';
        Setup.Modify();

        Assert.IsFalse(PackStationMgt.TryResolvePackingStation('', '', 'ANNEN-BRUKER', PackingStation), 'Ingen pakkebord skal gi false.');
        asserterror PackStationMgt.ResolvePackingStation('', '', 'ANNEN-BRUKER', PackingStation);
        Assert.IsTrue(StrPos(GetLastErrorText(), 'pakkebord') > 0, 'Feilmeldingen skal forklare at pakkebord mangler.');
    end;

    [Test]
    procedure SecretRoundTrip()
    var
        SecretMgt: Codeunit "nShift Secret Mgt. KBS";
        Value: SecretText;
    begin
        SecretMgt.DeleteSecret(TestSecretKeyTok);
        Assert.IsFalse(SecretMgt.HasSecret(TestSecretKeyTok), 'Hemmeligheten skal ikke finnes før den er satt.');

        Value := SecretStrSubstNo('abc123');
        SecretMgt.SetSecret(TestSecretKeyTok, Value);
        Assert.IsTrue(SecretMgt.HasSecret(TestSecretKeyTok), 'Hemmeligheten skal finnes etter at den er satt.');
        Assert.IsFalse(SecretMgt.GetSecret(TestSecretKeyTok, 'Test').IsEmpty(), 'Hemmeligheten skal kunne leses.');

        Clear(Value);
        SecretMgt.SetSecret(TestSecretKeyTok, Value);
        Assert.IsFalse(SecretMgt.HasSecret(TestSecretKeyTok), 'En tom verdi skal slette hemmeligheten.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure MissingLocationSetupGivesError()
    var
        LocationSetup: Record "nShift Location Setup KBS";
    begin
        asserterror LocationSetup.GetForLocation('NSH-NONE');
        Assert.IsTrue(StrPos(GetLastErrorText(), 'NSH-NONE') > 0, 'Feilen skal nevne lokasjonen.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure FreightRuleValidation()
    var
        FreightRule: Record "nShift Freight Rule KBS";
    begin
        FreightRule.Init();
        FreightRule.Validate(Scope, FreightRule.Scope::Customer);
        FreightRule."Scope Code" := 'K10000';
        FreightRule.Validate(Scope, FreightRule.Scope::"All Customers");
        Assert.AreEqual('', FreightRule."Scope Code", 'Bytte av omfang skal tømme koden.');

        FreightRule.Validate(Action, FreightRule.Action::"Percent Surcharge");
        FreightRule.Validate(Value, 15);
        FreightRule.Validate(Action, FreightRule.Action::"Free Freight");
        Assert.AreEqual(0, FreightRule.Value, 'Fraktfritt skal nullstille verdien.');

        FreightRule.Validate(Action, FreightRule.Action::"Percent Discount");
        asserterror FreightRule.Validate(Value, 150);

        FreightRule.Validate("Minimum Order Amount", 1000);
        asserterror FreightRule.Validate("Maximum Order Amount", 500);
    end;

    local procedure InsertPackingStation(PackingStationCode: Code[20]; IsBlocked: Boolean)
    var
        PackingStation: Record "nShift Packing Station KBS";
    begin
        PackingStation.Init();
        PackingStation.Code := PackingStationCode;
        PackingStation.Blocked := IsBlocked;
        PackingStation.Insert();
    end;

    local procedure CreateLocation(): Code[10]
    var
        Location: Record Location;
    begin
        Location.Init();
        Location.Code := 'NSH-TEST';
        if not Location.Insert() then;
        exit(Location.Code);
    end;
}
