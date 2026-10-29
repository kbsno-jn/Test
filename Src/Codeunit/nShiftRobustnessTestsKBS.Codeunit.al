namespace Knowit.nShift.Test;

using Knowit.nShift;

/// <summary>
/// Fase 6.1: regler for nye forsøk (bare tidsavbrudd/serverfeil, maks 3, 5/15/45 min), jobbkøens nye forsøk uten
/// utskrift, og rydding av API-loggen. Shipment Mgt. gjør Commit, så testene bruker AutoCommit og egne forsendelsesnr.
/// </summary>
codeunit 73977 "nShift Robustness Tests KBS"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "nShift Library Assert KBS";
        LibraryShipment: Codeunit "nShift Library Shipment KBS";
        HttpMock: Codeunit "nShift HTTP Mock KBS";
        ShipmentMgt: Codeunit "nShift Shipment Mgt. KBS";
        RetryJob: Codeunit "nShift Retry Job KBS";
        ServerErrorJsonTok: Label '{"Message":"Service unavailable"}', Locked = true;

    [Test]
    procedure OnlyTimeoutAndServerErrorsAreTransient()
    begin
        Assert.IsTrue(RetryJob.IsTransientStatusCode(0), 'Ingen svar (tidsavbrudd) er midlertidig.');
        Assert.IsTrue(RetryJob.IsTransientStatusCode(408), '408 er midlertidig.');
        Assert.IsTrue(RetryJob.IsTransientStatusCode(429), '429 er midlertidig.');
        Assert.IsTrue(RetryJob.IsTransientStatusCode(500), '500 er midlertidig.');
        Assert.IsTrue(RetryJob.IsTransientStatusCode(503), '503 er midlertidig.');
        Assert.IsFalse(RetryJob.IsTransientStatusCode(400), '400 må rettes av brukeren.');
        Assert.IsFalse(RetryJob.IsTransientStatusCode(401), '401 må rettes av brukeren.');
        Assert.IsFalse(RetryJob.IsTransientStatusCode(422), '422 må rettes av brukeren.');
    end;

    [Test]
    procedure BackoffIsFiveFifteenFortyFiveMinutes()
    var
        NextRetryAt: DateTime;
    begin
        Assert.AreEqual(3, RetryJob.GetMaxRetries(), 'Maks 3 automatiske forsøk.');
        Assert.AreEqual(5, RetryJob.GetRetryDelayMinutes(0), 'Første forsøk etter 5 min.');
        Assert.AreEqual(15, RetryJob.GetRetryDelayMinutes(1), 'Andre forsøk etter 15 min.');
        Assert.AreEqual(45, RetryJob.GetRetryDelayMinutes(2), 'Tredje forsøk etter 45 min.');
        NextRetryAt := RetryJob.GetNextRetryAt(0);
        Assert.IsTrue((NextRetryAt > CurrentDateTime() + 4 * 60000) and (NextRetryAt <= CurrentDateTime() + 5 * 60000), 'Neste forsøk om 5 min.');
        Assert.AreEqual(0DT, RetryJob.GetNextRetryAt(3), 'Ingen flere forsøk etter 3.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure ServerErrorOnPostedShipmentSchedulesRetry()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
    begin
        Initialize(ShipmentHeader, 'NSH-ROB01', true);
        HttpMock.EnqueueShipResponse(503, ServerErrorJsonTok);

        Assert.IsFalse(ShipmentMgt.CreateShipment(ShipmentHeader, TempLabelBuffer), 'Serverfeil skal gi false.');

        ShipmentHeader.Get(ShipmentHeader."No.");
        Assert.AreEqual(ShipmentHeader.Status::Error, ShipmentHeader.Status, 'Status skal være Feil.');
        Assert.IsTrue(ShipmentHeader."Next Retry At" > CurrentDateTime(), 'Jobbkøen skal prøve igjen senere.');
        Finish();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure RejectedShipmentIsNotRetried()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
    begin
        Initialize(ShipmentHeader, 'NSH-ROB02', true);
        HttpMock.EnqueueShipResponse(422, NavApp.GetResourceAsText('ship/error-invalid-weight.response.json'));

        Assert.IsFalse(ShipmentMgt.CreateShipment(ShipmentHeader, TempLabelBuffer), 'Avvisning skal gi false.');

        ShipmentHeader.Get(ShipmentHeader."No.");
        Assert.AreEqual(0DT, ShipmentHeader."Next Retry At", 'Avvisninger (4xx) skal rettes av brukeren, ikke prøves automatisk.');
        Finish();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure ManualShipmentIsNotRetried()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
    begin
        Initialize(ShipmentHeader, 'NSH-ROB03', false);
        HttpMock.EnqueueShipResponse(503, ServerErrorJsonTok);

        Assert.IsFalse(ShipmentMgt.CreateShipment(ShipmentHeader, TempLabelBuffer), 'Serverfeil skal gi false.');

        ShipmentHeader.Get(ShipmentHeader."No.");
        Assert.AreEqual(0DT, ShipmentHeader."Next Retry At", 'Forsendelser uten bokført følgeseddel prøves ikke i bakgrunnen.');
        Finish();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure RetryJobCreatesDueShipmentWithoutPrinting()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
    begin
        Initialize(ShipmentHeader, 'NSH-ROB04', true);
        ShipmentHeader.Status := ShipmentHeader.Status::Error;
        ShipmentHeader."Next Retry At" := CurrentDateTime() - 60000;
        ShipmentHeader.Modify();
        HttpMock.EnqueueShipResponse(201, NavApp.GetResourceAsText('ship/shipments-pdf.response.json'));
        HttpMock.EnqueueShipResponse(200, NavApp.GetResourceAsText('ship/trackingURL.response.json'));

        Assert.AreEqual(1, RetryJob.RetryFailedShipments(), 'Forsendelsen som står for tur, skal opprettes.');

        ShipmentHeader.Get(ShipmentHeader."No.");
        Assert.AreEqual(ShipmentHeader.Status::Created, ShipmentHeader.Status, 'Status skal være Opprettet: ' + ShipmentHeader."Last Error Text");
        Assert.AreEqual(1, ShipmentHeader."Retry Count", 'Forsøket skal telles.');
        Assert.AreEqual(0DT, ShipmentHeader."Next Retry At", 'Ingen flere forsøk etter opprettelse.');
        Assert.IsTrue(ShipmentHeader."Label Not Printed", 'Jobbkøen skriver ikke ut – etiketten skal markeres som ikke skrevet ut.');
        Finish();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoCommit)]
    procedure RetryJobSkipsShipmentNotDueYet()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
    begin
        Initialize(ShipmentHeader, 'NSH-ROB05', true);
        ShipmentHeader.Status := ShipmentHeader.Status::Error;
        ShipmentHeader."Next Retry At" := CurrentDateTime() + 600000;
        ShipmentHeader.Modify();

        RetryJob.RetryFailedShipments();

        ShipmentHeader.Get(ShipmentHeader."No.");
        Assert.AreEqual(ShipmentHeader.Status::Error, ShipmentHeader.Status, 'Forsendelsen skal vente til tidspunktet.');
        Assert.AreEqual(0, HttpMock.GetShipCalls(), 'nShift skal ikke kalles.');
        Finish();
    end;

    [Test]
    procedure LogCleanupDeletesOnlyExpiredEntries()
    var
        Setup: Record "nShift Setup KBS";
        ApiLog: Record "nShift API Log KBS";
        LogCleanup: Codeunit "nShift Log Cleanup KBS";
        OldEntryNo: BigInteger;
        NewEntryNo: BigInteger;
    begin
        Setup.GetRecordOnce();
        Setup."Log Retention Days" := 30;
        Setup.Modify();
        OldEntryNo := InsertLogEntry(CreateDateTime(Today() - 31, 120000T));
        NewEntryNo := InsertLogEntry(CreateDateTime(Today() - 29, 120000T));

        LogCleanup.DeleteExpiredEntries();

        Assert.IsFalse(ApiLog.Get(OldEntryNo), 'Loggpost eldre enn 30 dager skal slettes.');
        Assert.IsTrue(ApiLog.Get(NewEntryNo), 'Nyere loggpost skal beholdes.');
    end;

    [Test]
    procedure LogCleanupDoesNothingWithZeroRetention()
    var
        Setup: Record "nShift Setup KBS";
        ApiLog: Record "nShift API Log KBS";
        LogCleanup: Codeunit "nShift Log Cleanup KBS";
        OldEntryNo: BigInteger;
    begin
        Setup.GetRecordOnce();
        Setup."Log Retention Days" := 0;
        Setup.Modify();
        OldEntryNo := InsertLogEntry(CreateDateTime(Today() - 400, 120000T));

        Assert.AreEqual(0, LogCleanup.DeleteExpiredEntries(), '0 dager betyr ingen rydding.');
        Assert.IsTrue(ApiLog.Get(OldEntryNo), 'Loggposten skal beholdes.');
    end;

    local procedure Initialize(var ShipmentHeader: Record "nShift Shipment Header KBS"; ShipmentNo: Code[20]; FromPosting: Boolean)
    begin
        Clear(HttpMock);
        LibraryShipment.InitializeHttpMock(HttpMock);
        LibraryShipment.CreateShipment(ShipmentHeader, ShipmentNo);
        if FromPosting then begin
            ShipmentHeader."Posted Shipment No." := ShipmentNo;
            ShipmentHeader.Modify();
        end;
    end;

    local procedure Finish()
    begin
        UnbindSubscription(HttpMock);
    end;

    local procedure InsertLogEntry(LoggedAt: DateTime): BigInteger
    var
        ApiLog: Record "nShift API Log KBS";
    begin
        ApiLog.LogCall("nShift API Operation KBS"::CreateShipment, 'NSH-ROBLOG', '', 'GET', 'https://ship.example', '', '', 200, 0, true, '', '');
        ApiLog.FindLast();
        ApiLog."Logged At" := LoggedAt;
        ApiLog.Modify();
        exit(ApiLog."Entry No.");
    end;
}
