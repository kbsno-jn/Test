namespace Knowit.nShift.Test;

using Knowit.nShift;

/// <summary>
/// Tester API-klienten med mocket HTTP (ingen kall ut). Feilsvar hentes fra fixtures tatt opp mot nShift.
/// </summary>
codeunit 73965 "nShift API Client Tests KBS"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "nShift Library Assert KBS";
        HttpMock: Codeunit "nShift HTTP Mock KBS";
        TokenUrlTok: Label 'https://idp.example/connect/token', Locked = true;
        BaseUrlTok: Label 'https://ship.example', Locked = true;
        TokenJsonTok: Label '{"access_token":"tok-123","expires_in":3600,"token_type":"Bearer","scope":"public_api_shipmentserver"}', Locked = true;
        SenderAddressJsonTok: Label '{"Kind":2,"Name1":"Saferoad B.Berntsen AS","CountryCode":"NO","CorrelationID":"c-1"}', Locked = true;
        UnauthorizedJsonTok: Label '{"ErrorType":"Unauthorized","Message":"Unauthorized","Errors":[]}', Locked = true;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure TokenIsFetchedOnceAndReused()
    var
        ApiClient: Codeunit "nShift API Client KBS";
        ApiResponse: Codeunit "nShift API Response KBS";
    begin
        Initialize();
        HttpMock.EnqueueShipResponse(200, SenderAddressJsonTok);
        HttpMock.EnqueueShipResponse(200, SenderAddressJsonTok);

        Assert.IsTrue(ApiClient.Get("nShift API Operation KBS"::TestConnection, '/senderAddress', ApiResponse), 'Første kall skal lykkes.');
        Assert.IsTrue(ApiClient.Get("nShift API Operation KBS"::TestConnection, '/senderAddress', ApiResponse), 'Andre kall skal lykkes.');

        Assert.AreEqual(1, HttpMock.GetTokenCalls(), 'Tokenet skal hentes én gang og gjenbrukes.');
        Assert.AreEqual(2, HttpMock.GetShipCalls(), 'Begge kallene skal nå nShift Ship.');
        Assert.AreEqual('https://ship.example/ShipServer/13131/senderAddress', HttpMock.GetLastShipUrl(), 'URL bygges av base-URL, Actor-ID og sti.');
        Assert.AreEqual('GET', HttpMock.GetLastShipMethod(), 'Metoden skal være GET.');
        Assert.AreEqual('c-1', ApiResponse.GetCorrelationId(), 'Korrelasjons-ID leses fra svaret.');
        UnbindSubscription(HttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PostSendsJsonBody()
    var
        ApiClient: Codeunit "nShift API Client KBS";
        ApiResponse: Codeunit "nShift API Response KBS";
        RequestBody: JsonObject;
    begin
        Initialize();
        HttpMock.EnqueueShipResponse(200, '{"Messages":["Validation OK"]}');
        RequestBody.Add('Kind', 1);

        Assert.IsTrue(ApiClient.Post("nShift API Operation KBS"::ValidateShipment, '/shipmentValidations', RequestBody, ApiResponse), 'Kallet skal lykkes.');
        Assert.AreEqual('POST', HttpMock.GetLastShipMethod(), 'Metoden skal være POST.');
        Assert.AreEqual('{"Kind":1}', HttpMock.GetLastShipRequestBody(), 'JSON-kroppen skal sendes uendret.');
        UnbindSubscription(HttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure TokenIsNeverLogged()
    var
        ApiLog: Record "nShift API Log KBS";
        ApiClient: Codeunit "nShift API Client KBS";
        ApiResponse: Codeunit "nShift API Response KBS";
    begin
        Initialize();
        HttpMock.EnqueueShipResponse(200, SenderAddressJsonTok);
        ApiLog.DeleteAll();

        ApiClient.Get("nShift API Operation KBS"::TestConnection, '/senderAddress', ApiResponse);

        Assert.AreEqual(2, ApiLog.Count(), 'Token-kallet og Ship-kallet skal logges.');
        ApiLog.SetRange(Operation, "nShift API Operation KBS"::GetAccessToken);
        ApiLog.FindFirst();
        Assert.IsFalse(ApiLog.GetResponseBody().Contains('tok-123'), 'Tokenet skal ikke stå i loggen.');
        Assert.IsFalse(ApiLog.GetRequestBody().Contains('client_secret'), 'Client Secret skal ikke stå i loggen.');
        Assert.IsTrue(ApiLog.Success, 'Token-kallet skal logges som vellykket.');
        // Nøyaktig én Content-Type – to verdier (text/plain + form) ga invalid_request fra nShift.
        Assert.IsTrue(ApiLog.GetRequestBody().Contains('Content-Type: application/x-www-form-urlencoded>'), 'Token-kallet skal sendes som skjema og bare det: ' + ApiLog.GetRequestBody());
        UnbindSubscription(HttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure UnauthorizedRetriesOnceWithNewToken()
    var
        ApiClient: Codeunit "nShift API Client KBS";
        ApiResponse: Codeunit "nShift API Response KBS";
    begin
        Initialize();
        HttpMock.EnqueueShipResponse(401, UnauthorizedJsonTok);
        HttpMock.EnqueueShipResponse(200, SenderAddressJsonTok);

        Assert.IsTrue(ApiClient.Get("nShift API Operation KBS"::TestConnection, '/senderAddress', ApiResponse), 'Kallet skal lykkes etter nytt token.');
        Assert.AreEqual(2, HttpMock.GetTokenCalls(), 'Nytt token skal hentes etter 401.');
        Assert.AreEqual(2, HttpMock.GetShipCalls(), 'Kallet skal prøves nøyaktig én gang til.');
        UnbindSubscription(HttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure RepeatedUnauthorizedGivesSetupError()
    var
        ApiClient: Codeunit "nShift API Client KBS";
        ApiResponse: Codeunit "nShift API Response KBS";
    begin
        Initialize();
        HttpMock.EnqueueShipResponse(401, UnauthorizedJsonTok);
        HttpMock.EnqueueShipResponse(401, UnauthorizedJsonTok);

        Assert.IsFalse(ApiClient.Get("nShift API Operation KBS"::TestConnection, '/senderAddress', ApiResponse), 'Kallet skal feile.');
        Assert.AreEqual(2, HttpMock.GetShipCalls(), 'Ikke flere enn ett nytt forsøk.');
        Assert.IsTrue(ApiResponse.GetErrorText().Contains('Actor-ID'), 'Meldingen skal peke på oppsettet.');
        UnbindSubscription(HttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure RejectedClientGivesReadableError()
    var
        ApiClient: Codeunit "nShift API Client KBS";
        ApiResponse: Codeunit "nShift API Response KBS";
    begin
        Initialize();
        HttpMock.Initialize(TokenUrlTok, 400, '{"error":"invalid_client"}');

        Assert.IsFalse(ApiClient.Get("nShift API Operation KBS"::TestConnection, '/senderAddress', ApiResponse), 'Kallet skal feile.');
        Assert.AreEqual(0, HttpMock.GetShipCalls(), 'Ship skal ikke kalles uten token.');
        Assert.IsTrue(ApiResponse.GetErrorText().Contains('invalid_client'), 'Feilkoden fra token-tjenesten skal vises.');
        Assert.IsTrue(ApiResponse.GetErrorText().Contains('Client Secret'), 'Meldingen skal peke på oppsettet.');
        UnbindSubscription(HttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure ValidationErrorShowsNShiftMessages()
    var
        ApiClient: Codeunit "nShift API Client KBS";
        ApiResponse: Codeunit "nShift API Response KBS";
        RequestBody: JsonObject;
        Fixture: JsonObject;
        FixtureText: Text;
        CorrelationToken: JsonToken;
    begin
        Initialize();
        // Forventet korrelasjons-ID leses fra fixturen, så testen tåler at fixturene tas opp på nytt.
        FixtureText := NavApp.GetResourceAsText('ship/error-validation-weight.response.json');
        Fixture.ReadFrom(FixtureText);
        Fixture.Get('CorrelationID', CorrelationToken);
        HttpMock.EnqueueShipResponse(422, FixtureText);

        Assert.IsFalse(ApiClient.Post("nShift API Operation KBS"::ValidateShipment, '/shipmentValidations', RequestBody, ApiResponse), 'Valideringsfeil skal gi false.');
        Assert.AreEqual(422, ApiResponse.GetStatusCode(), 'Statuskoden skal tas vare på.');
        Assert.IsTrue(ApiResponse.GetErrorText().Contains('(422)'), 'Meldingen skal vise statuskoden.');
        Assert.IsTrue(ApiResponse.GetErrorText().Contains('Maximum weight per product cannot exceed 35 kg.'), 'Feilen fra Errors[] skal tas med.');
        Assert.IsTrue(ApiResponse.GetErrorText().Contains(CorrelationToken.AsValue().AsText()), 'Korrelasjons-ID skal tas med: ' + ApiResponse.GetErrorText());
        UnbindSubscription(HttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure UnknownActorGivesNotFound()
    var
        ApiLog: Record "nShift API Log KBS";
        ApiClient: Codeunit "nShift API Client KBS";
        ApiResponse: Codeunit "nShift API Response KBS";
    begin
        Initialize();
        HttpMock.EnqueueShipResponse(404, '{"ErrorType":"Not Found","Message":"Cannot find actor with ID 13131","Errors":[],"CorrelationID":"c-404"}');
        ApiLog.DeleteAll();
        ApiClient.SetContext('NSH000001', '');

        Assert.IsFalse(ApiClient.Get("nShift API Operation KBS"::GetShipment, '/shipments/X', ApiResponse), '404 skal gi false.');
        Assert.IsTrue(ApiResponse.GetErrorText().Contains('Cannot find actor with ID 13131'), 'nShift sin melding skal vises.');

        ApiLog.SetRange(Operation, "nShift API Operation KBS"::GetShipment);
        ApiLog.FindFirst();
        Assert.AreEqual('NSH000001', ApiLog."Shipment No.", 'Loggen skal kobles til forsendelsen.');
        Assert.AreEqual('c-404', ApiLog."Correlation ID", 'Korrelasjons-ID skal logges.');
        Assert.AreEqual(404, ApiLog."Status Code", 'Statuskoden skal logges.');
        Assert.IsFalse(ApiLog.Success, 'Kallet skal logges som feilet.');
        UnbindSubscription(HttpMock);
    end;

    [Test]
    procedure ServerErrorTextAsksToRetry()
    var
        ApiClient: Codeunit "nShift API Client KBS";
        ErrorText: Text;
    begin
        ErrorText := ApiClient.BuildErrorText(503, 'Service Unavailable', '', false);
        Assert.IsTrue(ErrorText.Contains('(503)'), 'Statuskoden skal vises.');
        Assert.IsTrue(ErrorText.Contains('Prøv igjen senere'), '5xx skal be brukeren prøve igjen.');
    end;

    [Test]
    procedure CachedTokenRespectsExpiry()
    var
        SecretMgt: Codeunit "nShift Secret Mgt. KBS";
        Token: SecretText;
    begin
        SecretMgt.SetShipAccessToken(SecretStrSubstNo('tok'), CurrentDateTime() + 30000);
        Assert.IsFalse(SecretMgt.TryGetShipAccessToken(Token), 'Token som utløper innen ett minutt skal ikke brukes.');

        SecretMgt.SetShipAccessToken(SecretStrSubstNo('tok'), CurrentDateTime() + 3600000);
        Assert.IsTrue(SecretMgt.TryGetShipAccessToken(Token), 'Gyldig token skal gjenbrukes.');

        SecretMgt.ClearShipAccessToken();
        Assert.IsFalse(SecretMgt.TryGetShipAccessToken(Token), 'Slettet token skal ikke finnes.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure ChangingClientIdClearsToken()
    var
        Setup: Record "nShift Setup KBS";
        SecretMgt: Codeunit "nShift Secret Mgt. KBS";
        Token: SecretText;
    begin
        Setup.GetRecordOnce();
        SecretMgt.SetShipAccessToken(SecretStrSubstNo('tok'), CurrentDateTime() + 3600000);
        Setup.Validate("Client ID", '  cc_annen  ');
        Assert.AreEqual('cc_annen', Setup."Client ID", 'Client ID skal trimmes.');
        Assert.IsFalse(SecretMgt.TryGetShipAccessToken(Token), 'Bytte av Client ID skal slette bufret token.');
    end;

    local procedure Initialize()
    var
        Setup: Record "nShift Setup KBS";
        SecretMgt: Codeunit "nShift Secret Mgt. KBS";
    begin
        Clear(HttpMock);
        HttpMock.Initialize(TokenUrlTok, 200, TokenJsonTok);
        BindSubscription(HttpMock);

        Setup.GetRecordOnce();
        Setup."Base URL" := BaseUrlTok;
        Setup."Token URL" := TokenUrlTok;
        Setup."Actor ID" := 13131;
        Setup."Client ID" := 'cc_test';
        Setup."Request Timeout (ms)" := 30000;
        Setup.Modify();
        SecretMgt.SetShipClientSecretFormEncoded(SecretStrSubstNo('s%2Bcret'));
        SecretMgt.ClearShipAccessToken();
    end;
}
