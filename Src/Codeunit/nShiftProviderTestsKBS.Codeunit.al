namespace Knowit.nShift.Test;

using Knowit.nShift;

codeunit 73962 "nShift Provider Tests KBS"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "nShift Library Assert KBS";

    [Test]
    procedure ShipProviderResolvesFromEnum()
    var
        Provider: Interface "nShift ICarrier Provider KBS";
    begin
        Provider := "nShift Provider KBS"::Ship;
        Assert.AreEqual('nShift Ship', Provider.GetDisplayName(), 'Ship-verdien skal peke på Ship-provideren.');
    end;

    [Test]
    procedure MockProviderResolvesFromEnumExtension()
    var
        Provider: Interface "nShift ICarrier Provider KBS";
        ErrorText: Text;
    begin
        Provider := "nShift Provider KBS"::"Mock KBS";
        Assert.AreEqual('Mock', Provider.GetDisplayName(), 'Mock-verdien skal peke på mock-provideren.');
        Assert.IsTrue(Provider.TestConnection(ErrorText), 'Mock-provideren skal alltid ha tilkobling.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure ShipProviderTestConnectionSucceeds()
    var
        HttpMock: Codeunit "nShift HTTP Mock KBS";
        Provider: Interface "nShift ICarrier Provider KBS";
        ErrorText: Text;
    begin
        InitializeShipSetup(HttpMock);
        HttpMock.EnqueueShipResponse(200, '{"Kind":2,"Name1":"Saferoad B.Berntsen AS"}');

        Provider := "nShift Provider KBS"::Ship;
        Assert.IsTrue(Provider.TestConnection(ErrorText), 'Tilkoblingen skal være i orden: ' + ErrorText);
        Assert.IsTrue(HttpMock.GetLastShipUrl().EndsWith('/ShipServer/13131/senderAddress'), 'Tilkoblingstesten skal hente avsenderadressen.');
        UnbindSubscription(HttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure ShipProviderTestConnectionReportsError()
    var
        HttpMock: Codeunit "nShift HTTP Mock KBS";
        Provider: Interface "nShift ICarrier Provider KBS";
        ErrorText: Text;
    begin
        InitializeShipSetup(HttpMock);
        HttpMock.EnqueueShipResponse(404, '{"ErrorType":"Not Found","Message":"Cannot find actor with ID 13131","Errors":[]}');

        Provider := "nShift Provider KBS"::Ship;
        Assert.IsFalse(Provider.TestConnection(ErrorText), 'Ukjent Actor skal gi feil.');
        Assert.IsTrue(ErrorText.Contains('Cannot find actor'), 'Feilmeldingen fra nShift skal returneres.');
        UnbindSubscription(HttpMock);
    end;

    /// <summary>
    /// Oppsett med mocket HTTP, slik at testen aldri kaller nShift – uansett hva som står i sandkassens oppsett.
    /// </summary>
    local procedure InitializeShipSetup(var HttpMock: Codeunit "nShift HTTP Mock KBS")
    var
        Setup: Record "nShift Setup KBS";
        SecretMgt: Codeunit "nShift Secret Mgt. KBS";
    begin
        HttpMock.Initialize('https://idp.example/connect/token', 200, '{"access_token":"tok","expires_in":3600}');
        BindSubscription(HttpMock);
        Setup.GetRecordOnce();
        Setup."Base URL" := 'https://ship.example';
        Setup."Token URL" := 'https://idp.example/connect/token';
        Setup."Actor ID" := 13131;
        Setup."Client ID" := 'cc_test';
        Setup.Modify();
        SecretMgt.SetShipClientSecretFormEncoded(SecretStrSubstNo('secret'));
        SecretMgt.ClearShipAccessToken();
    end;
}
