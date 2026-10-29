namespace Knowit.nShift.Test;

using Knowit.nShift;

/// <summary>
/// Etikettskriver uten utskrift. SingleInstance, slik at testen kan lese hva som ble «skrevet ut» – nullstill med Reset.
/// </summary>
codeunit 73971 "nShift Printer Mock KBS" implements "nShift ILabel Printer KBS"
{
    SingleInstance = true;

    var
        PrintCount: Integer;
        PrintedLabelCount: Integer;
        LastPackingStationCode: Code[20];
        FailWithErrorText: Text;
        DisplayNameLbl: Label 'Mock-skriver', Locked = true;

    procedure Reset()
    begin
        PrintCount := 0;
        PrintedLabelCount := 0;
        LastPackingStationCode := '';
        FailWithErrorText := '';
    end;

    /// <summary>
    /// Neste utskrift feiler med denne meldingen.
    /// </summary>
    procedure SetFailure(NewErrorText: Text)
    begin
        FailWithErrorText := NewErrorText;
    end;

    procedure GetPrintCount(): Integer
    begin
        exit(PrintCount);
    end;

    procedure GetPrintedLabelCount(): Integer
    begin
        exit(PrintedLabelCount);
    end;

    procedure GetLastPackingStationCode(): Code[20]
    begin
        exit(LastPackingStationCode);
    end;

    procedure GetDisplayName(): Text
    begin
        exit(DisplayNameLbl);
    end;

    procedure SupportsFormat(LabelFormat: Enum "nShift Label Format KBS"): Boolean
    begin
        exit(true);
    end;

    procedure Print(var LabelBuffer: Record "nShift Label Buffer KBS"; PackingStation: Record "nShift Packing Station KBS"; var ErrorText: Text): Boolean
    begin
        ErrorText := FailWithErrorText;
        if ErrorText <> '' then
            exit(false);
        PrintCount += 1;
        PrintedLabelCount += LabelBuffer.Count();
        LastPackingStationCode := PackingStation.Code;
        exit(true);
    end;

    procedure GetPrinters(var PrinterBuffer: Record "nShift Printer Buffer KBS"; var ErrorText: Text): Boolean
    begin
        ErrorText := '';
        PrinterBuffer.Init();
        PrinterBuffer.ID := 'MOCK-1';
        PrinterBuffer.Name := 'Mock-skriver 1';
        PrinterBuffer.Insert();
        exit(true);
    end;
}
