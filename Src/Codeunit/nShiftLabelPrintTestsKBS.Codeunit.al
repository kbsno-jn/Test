namespace Knowit.nShift.Test;

using Knowit.nShift;
using Microsoft.Foundation.Attachment;

/// <summary>
/// Tester etikettutskrift (2.7): PrintNode mot mocket HTTP, formatkontroll på pakkebord, ruting til pakkebordets
/// skriver (mock-skriver), utskriftsfeil som ikke endrer status, og etikett som vedlegg.
/// PrintNode-svarene er laget etter dokumentasjonen – ikke tatt opp mot en konto ennå.
/// </summary>
codeunit 73973 "nShift Label Print Tests KBS"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "nShift Library Assert KBS";
        LibraryShipment: Codeunit "nShift Library Shipment KBS";
        PrinterHttpMock: Codeunit "nShift Printer Http Mock KBS";
        PrinterMock: Codeunit "nShift Printer Mock KBS";
        ShipmentNoTok: Label 'NSH-LBL1', Locked = true;
        PdfContentTok: Label 'JVBERi0xLjcK', Locked = true;
        ZplContentTok: Label 'XlhBXkZPNTAsNTBeRkRUZXN0XkZTXlha', Locked = true;
        PackageNoTok: Label 'PKG-%1', Locked = true, Comment = '%1 = løpenr.';

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PrintNodeSendsPdfPrintJob()
    var
        PackingStation: Record "nShift Packing Station KBS";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
        PrintNodePrinter: Codeunit "nShift PrintNode Printer KBS";
        ErrorText: Text;
    begin
        InitializePrintNode(201, '473');
        CreatePackingStation(PackingStation, "nShift Label Printer KBS"::PrintNode, "nShift Label Format KBS"::PDF, '12345');
        AddLabel(TempLabelBuffer, "nShift Label Format KBS"::PDF, PdfContentTok);

        Assert.IsTrue(PrintNodePrinter.Print(TempLabelBuffer, PackingStation, ErrorText), 'Utskriften skal lykkes: ' + ErrorText);

        Assert.AreEqual('POST', PrinterHttpMock.GetLastMethod(), 'Utskriftsjobb er POST.');
        Assert.AreEqual('https://printnode.example/printjobs', PrinterHttpMock.GetLastUrl(), 'Jobben sendes til /printjobs.');
        Assert.IsTrue(PrinterHttpMock.GetLastRequestBody().Contains('"printerId":12345'), 'Skriver-ID sendes som tall: ' + PrinterHttpMock.GetLastRequestBody());
        Assert.IsTrue(PrinterHttpMock.GetLastRequestBody().Contains('"contentType":"pdf_base64"'), 'PDF sendes som pdf_base64.');
        Assert.IsTrue(PrinterHttpMock.GetLastRequestBody().Contains('"content":"' + PdfContentTok + '"'), 'Etikettinnholdet sendes.');
        UnbindSubscription(PrinterHttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PrintNodeLogDoesNotContainLabelContent()
    var
        PackingStation: Record "nShift Packing Station KBS";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
        ApiLog: Record "nShift API Log KBS";
        PrintNodePrinter: Codeunit "nShift PrintNode Printer KBS";
        ErrorText: Text;
    begin
        InitializePrintNode(201, '473');
        ApiLog.DeleteAll();
        CreatePackingStation(PackingStation, "nShift Label Printer KBS"::PrintNode, "nShift Label Format KBS"::PDF, '12345');
        AddLabel(TempLabelBuffer, "nShift Label Format KBS"::PDF, PdfContentTok);

        PrintNodePrinter.Print(TempLabelBuffer, PackingStation, ErrorText);

        ApiLog.SetRange(Operation, "nShift API Operation KBS"::PrintLabel);
        Assert.IsTrue(ApiLog.FindFirst(), 'Utskriften skal logges.');
        Assert.IsFalse(ApiLog.GetRequestBody().Contains(PdfContentTok), 'Etikettinnholdet skal ikke fylle loggen.');
        Assert.IsTrue(ApiLog.GetRequestBody().Contains('<etikett,'), 'Loggen skal vise at en etikett ble sendt.');
        UnbindSubscription(PrinterHttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PrintNodeSendsZplAsRaw()
    var
        PackingStation: Record "nShift Packing Station KBS";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
        PrintNodePrinter: Codeunit "nShift PrintNode Printer KBS";
        ErrorText: Text;
    begin
        InitializePrintNode(201, '474');
        CreatePackingStation(PackingStation, "nShift Label Printer KBS"::PrintNode, "nShift Label Format KBS"::ZPL, '12345');
        AddLabel(TempLabelBuffer, "nShift Label Format KBS"::ZPL, ZplContentTok);

        Assert.IsTrue(PrintNodePrinter.Print(TempLabelBuffer, PackingStation, ErrorText), 'Utskriften skal lykkes: ' + ErrorText);
        Assert.IsTrue(PrinterHttpMock.GetLastRequestBody().Contains('"contentType":"raw_base64"'), 'ZPL sendes som raw_base64.');
        UnbindSubscription(PrinterHttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PrintNodeRejectsInvalidPrinterId()
    var
        PackingStation: Record "nShift Packing Station KBS";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
        PrintNodePrinter: Codeunit "nShift PrintNode Printer KBS";
        ErrorText: Text;
    begin
        InitializePrintNode(201, '473');
        CreatePackingStation(PackingStation, "nShift Label Printer KBS"::PrintNode, "nShift Label Format KBS"::PDF, 'Zebra');
        AddLabel(TempLabelBuffer, "nShift Label Format KBS"::PDF, PdfContentTok);

        Assert.IsFalse(PrintNodePrinter.Print(TempLabelBuffer, PackingStation, ErrorText), 'Skriver-ID som ikke er tall skal avvises.');
        Assert.IsTrue(ErrorText.Contains('gyldig PrintNode-skriver-ID'), 'Feilen skal forklare hvorfor: ' + ErrorText);
        Assert.AreEqual(0, PrinterHttpMock.GetCallCount(), 'PrintNode skal ikke kalles.');
        UnbindSubscription(PrinterHttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PrintNodeUnauthorizedPointsToApiKey()
    var
        PackingStation: Record "nShift Packing Station KBS";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
        PrintNodePrinter: Codeunit "nShift PrintNode Printer KBS";
        ErrorText: Text;
    begin
        InitializePrintNode(401, '{"code":"Unauthorized","message":"API Key not found"}');
        CreatePackingStation(PackingStation, "nShift Label Printer KBS"::PrintNode, "nShift Label Format KBS"::PDF, '12345');
        AddLabel(TempLabelBuffer, "nShift Label Format KBS"::PDF, PdfContentTok);

        Assert.IsFalse(PrintNodePrinter.Print(TempLabelBuffer, PackingStation, ErrorText), '401 skal gi false.');
        Assert.IsTrue(ErrorText.Contains('API-nøkkelen'), 'Meldingen skal peke på API-nøkkelen: ' + ErrorText);
        Assert.IsTrue(ErrorText.Contains('API Key not found'), 'Meldingen fra PrintNode skal tas med: ' + ErrorText);
        UnbindSubscription(PrinterHttpMock);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PrintNodeListsPrinters()
    var
        TempPrinterBuffer: Record "nShift Printer Buffer KBS" temporary;
        PrintNodePrinter: Codeunit "nShift PrintNode Printer KBS";
        ErrorText: Text;
    begin
        InitializePrintNode(200, '[{"id":34,"name":"Zebra GK420d","description":"Etikettskriver","state":"online","computer":{"id":7,"name":"PAKK-PC1"}}]');

        Assert.IsTrue(PrintNodePrinter.GetPrinters(TempPrinterBuffer, ErrorText), 'Skriverne skal hentes: ' + ErrorText);

        Assert.AreEqual('GET', PrinterHttpMock.GetLastMethod(), 'Skriverlisten hentes med GET.');
        Assert.AreEqual('https://printnode.example/printers', PrinterHttpMock.GetLastUrl(), 'Skriverlisten hentes fra /printers.');
        Assert.IsTrue(TempPrinterBuffer.Get('34'), 'Skriveren skal ha ID 34.');
        Assert.AreEqual('Zebra GK420d', TempPrinterBuffer.Name, 'Skrivernavnet skal leses.');
        Assert.IsTrue(TempPrinterBuffer.Description.Contains('PAKK-PC1'), 'Maskinen skriveren står på skal vises.');
        Assert.AreEqual('online', TempPrinterBuffer.State, 'Status skal leses.');
        UnbindSubscription(PrinterHttpMock);
    end;

    [Test]
    procedure ProvidersSupportTheRightFormats()
    var
        PrintNodePrinter: Codeunit "nShift PrintNode Printer KBS";
        BCLabelPrinter: Codeunit "nShift BC Label Printer KBS";
    begin
        Assert.IsTrue(PrintNodePrinter.SupportsFormat("nShift Label Format KBS"::PDF), 'PrintNode støtter PDF.');
        Assert.IsTrue(PrintNodePrinter.SupportsFormat("nShift Label Format KBS"::ZPL), 'PrintNode støtter ZPL.');
        Assert.IsFalse(PrintNodePrinter.SupportsFormat("nShift Label Format KBS"::PNG), 'PrintNode støtter ikke PNG.');
        Assert.IsTrue(BCLabelPrinter.SupportsFormat("nShift Label Format KBS"::PNG), 'BC-utskrift støtter PNG.');
        Assert.IsFalse(BCLabelPrinter.SupportsFormat("nShift Label Format KBS"::PDF), 'BC-utskrift støtter ikke PDF.');
        Assert.IsFalse(BCLabelPrinter.SupportsFormat("nShift Label Format KBS"::ZPL), 'BC-utskrift støtter ikke ZPL.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PackingStationRejectsUnsupportedFormat()
    var
        PackingStation: Record "nShift Packing Station KBS";
    begin
        PackingStation.Init();
        PackingStation.Code := 'PS-FMT';
        PackingStation.Validate("Printer Provider", PackingStation."Printer Provider"::"BC Standard");
        Assert.AreEqual(PackingStation."Label Format"::PNG, PackingStation."Label Format", 'BC-utskrift skal få PNG automatisk.');

        asserterror PackingStation.Validate("Label Format", PackingStation."Label Format"::ZPL);
        Assert.IsTrue(GetLastErrorText().Contains('ZPL'), 'ZPL med BC-utskrift skal avvises: ' + GetLastErrorText());
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure ChangingProviderPicksSupportedFormat()
    var
        PackingStation: Record "nShift Packing Station KBS";
    begin
        PackingStation.Init();
        PackingStation.Code := 'PS-SWITCH';
        PackingStation.Validate("Printer Provider", PackingStation."Printer Provider"::"BC Standard");
        PackingStation."Printer ID" := 'Universal Print 1';

        PackingStation.Validate("Printer Provider", PackingStation."Printer Provider"::PrintNode);

        Assert.AreEqual(PackingStation."Label Format"::PDF, PackingStation."Label Format", 'PNG skal byttes til et format PrintNode støtter.');
        Assert.AreEqual('', PackingStation."Printer ID", 'Skriveren skal nullstilles når provideren byttes.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure LabelsArePrintedAtShipmentPackingStation()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        PackingStation: Record "nShift Packing Station KBS";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
        LabelPrintMgt: Codeunit "nShift Label Print Mgt. KBS";
        ErrorText: Text;
    begin
        LibraryShipment.CreateShipment(ShipmentHeader, ShipmentNoTok);
        CreatePackingStation(PackingStation, "nShift Label Printer KBS"::"Mock KBS", "nShift Label Format KBS"::PDF, 'MOCK-1');
        PrinterMock.Reset();
        AddLabel(TempLabelBuffer, "nShift Label Format KBS"::PDF, PdfContentTok);
        AddLabel(TempLabelBuffer, "nShift Label Format KBS"::PDF, PdfContentTok);

        Assert.IsTrue(LabelPrintMgt.PrintLabels(ShipmentHeader, TempLabelBuffer, PackingStation.Code, ErrorText), 'Utskriften skal lykkes: ' + ErrorText);
        Assert.AreEqual(1, PrinterMock.GetPrintCount(), 'Skriveren skal kalles én gang.');
        Assert.AreEqual(2, PrinterMock.GetPrintedLabelCount(), 'Begge etikettene skal sendes.');
        Assert.AreEqual(PackingStation.Code, PrinterMock.GetLastPackingStationCode(), 'Pakkebordets skriver skal brukes.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PrintErrorIsStoredButStatusIsKept()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        PackingStation: Record "nShift Packing Station KBS";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
        LabelPrintMgt: Codeunit "nShift Label Print Mgt. KBS";
        ErrorText: Text;
    begin
        LibraryShipment.CreateShipment(ShipmentHeader, ShipmentNoTok);
        CreatePackingStation(PackingStation, "nShift Label Printer KBS"::"Mock KBS", "nShift Label Format KBS"::PDF, 'MOCK-1');
        ShipmentHeader.Status := ShipmentHeader.Status::Created;
        ShipmentHeader."Packing Station Code" := PackingStation.Code;
        ShipmentHeader.Modify();
        PrinterMock.Reset();
        PrinterMock.SetFailure('Tomt for etiketter');
        AddLabel(TempLabelBuffer, "nShift Label Format KBS"::PDF, PdfContentTok);

        Assert.IsFalse(LabelPrintMgt.HandleCreatedLabels(ShipmentHeader, TempLabelBuffer, ErrorText), 'Utskriftsfeilen skal rapporteres.');

        ShipmentHeader.Get(ShipmentHeader."No.");
        Assert.AreEqual(ShipmentHeader.Status::Created, ShipmentHeader.Status, 'Forsendelsen er fortsatt opprettet i nShift.');
        Assert.IsTrue(ShipmentHeader."Last Error Text".Contains('Tomt for etiketter'), 'Feilen skal lagres på forsendelsen: ' + ShipmentHeader."Last Error Text");
        PrinterMock.Reset();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure MissingPackingStationGivesReadableError()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        Setup: Record "nShift Setup KBS";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
        LabelPrintMgt: Codeunit "nShift Label Print Mgt. KBS";
        ErrorText: Text;
    begin
        LibraryShipment.CreateShipment(ShipmentHeader, ShipmentNoTok);
        LibraryShipment.ClearPackingStationDefaults();
        Setup.GetRecordOnce();
        Setup."Default Packing Station Code" := '';
        Setup.Modify();
        AddLabel(TempLabelBuffer, "nShift Label Format KBS"::PDF, PdfContentTok);

        Assert.IsFalse(LabelPrintMgt.PrintLabels(ShipmentHeader, TempLabelBuffer, '', ErrorText), 'Uten pakkebord kan det ikke skrives ut.');
        Assert.IsTrue(ErrorText.Contains('pakkebord'), 'Feilen skal forklare at pakkebord mangler: ' + ErrorText);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure LabelIsStoredAsAttachment()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        Setup: Record "nShift Setup KBS";
        DocumentAttachment: Record "Document Attachment";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
        LabelPrintMgt: Codeunit "nShift Label Print Mgt. KBS";
    begin
        LibraryShipment.CreateShipment(ShipmentHeader, ShipmentNoTok);
        Setup.GetRecordOnce();
        Setup."Store Label as Attachment" := true;
        Setup.Modify();
        AddLabel(TempLabelBuffer, "nShift Label Format KBS"::PDF, PdfContentTok);

        LabelPrintMgt.AttachLabels(ShipmentHeader, TempLabelBuffer);

        DocumentAttachment.SetRange("Table ID", Database::"nShift Shipment Header KBS");
        DocumentAttachment.SetRange("No.", ShipmentHeader."No.");
        Assert.AreEqual(1, DocumentAttachment.Count(), 'Etiketten skal lagres som vedlegg på forsendelsen.');
        DocumentAttachment.FindFirst();
        Assert.AreEqual('pdf', DocumentAttachment."File Extension", 'Vedlegget skal ha filtypen pdf.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure NoAttachmentWhenSetupIsOff()
    var
        ShipmentHeader: Record "nShift Shipment Header KBS";
        Setup: Record "nShift Setup KBS";
        DocumentAttachment: Record "Document Attachment";
        TempLabelBuffer: Record "nShift Label Buffer KBS" temporary;
        LabelPrintMgt: Codeunit "nShift Label Print Mgt. KBS";
    begin
        LibraryShipment.CreateShipment(ShipmentHeader, ShipmentNoTok);
        Setup.GetRecordOnce();
        Setup."Store Label as Attachment" := false;
        Setup.Modify();
        AddLabel(TempLabelBuffer, "nShift Label Format KBS"::PDF, PdfContentTok);

        LabelPrintMgt.AttachLabels(ShipmentHeader, TempLabelBuffer);

        DocumentAttachment.SetRange("Table ID", Database::"nShift Shipment Header KBS");
        DocumentAttachment.SetRange("No.", ShipmentHeader."No.");
        Assert.IsTrue(DocumentAttachment.IsEmpty(), 'Ingen vedlegg når oppsettet er av.');
    end;

    local procedure InitializePrintNode(Status: Integer; Body: Text)
    var
        Setup: Record "nShift Setup KBS";
        SecretMgt: Codeunit "nShift Secret Mgt. KBS";
    begin
        Clear(PrinterHttpMock);
        PrinterHttpMock.Initialize(Status, Body);
        BindSubscription(PrinterHttpMock);
        Setup.GetRecordOnce();
        Setup."PrintNode Base URL" := 'https://printnode.example/';
        Setup.Modify();
        SecretMgt.SetPrintNodeApiKey(SecretStrSubstNo('test-key'));
    end;

    local procedure CreatePackingStation(var PackingStation: Record "nShift Packing Station KBS"; PrinterProvider: Enum "nShift Label Printer KBS"; LabelFormat: Enum "nShift Label Format KBS"; PrinterId: Text[250])
    begin
        PackingStation.Init();
        PackingStation.Code := 'PS-TEST';
        PackingStation."Printer Provider" := PrinterProvider;
        PackingStation."Label Format" := LabelFormat;
        PackingStation."Printer ID" := PrinterId;
        if not PackingStation.Insert() then
            PackingStation.Modify();
    end;

    local procedure AddLabel(var TempLabelBuffer: Record "nShift Label Buffer KBS" temporary; LabelFormat: Enum "nShift Label Format KBS"; ContentBase64: Text)
    var
        EntryNo: Integer;
    begin
        TempLabelBuffer.Reset();
        if TempLabelBuffer.FindLast() then
            EntryNo := TempLabelBuffer."Entry No.";
        TempLabelBuffer.Init();
        TempLabelBuffer."Entry No." := EntryNo + 1;
        TempLabelBuffer."Shipment No." := ShipmentNoTok;
        TempLabelBuffer."Package Tracking No." := StrSubstNo(PackageNoTok, EntryNo + 1);
        TempLabelBuffer.Format := LabelFormat;
        TempLabelBuffer.Copies := 1;
        TempLabelBuffer.SetContentBase64(ContentBase64);
        TempLabelBuffer.Insert();
    end;
}
