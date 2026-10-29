namespace Knowit.nShift.Test;

using Knowit.nShift;

/// <summary>
/// Provider uten nettverkskall, for tester av forretningslogikk (Shipment Mgt., bokføring). Gir faste,
/// forutsigbare svar: MOCK-&lt;forsendelsesnr.&gt; som ShpTag og én PDF-etikett per kolli.
/// SingleInstance, slik at testen kan telle opprettelser og få neste opprettelse til å feile (SetCreateFailure).
/// Nullstill med Reset i starten av testen.
/// </summary>
codeunit 73960 "nShift Provider Mock KBS" implements "nShift ICarrier Provider KBS"
{
    SingleInstance = true;

    var
        CreateCount: Integer;
        TransmitCount: Integer;
        DeleteCount: Integer;
        CreateFailureText: Text;
        DisplayNameLbl: Label 'Mock', Locked = true;
        PackageTrackingNoTok: Label '%1-%2', Locked = true, Comment = '%1 = forsendelsesnr., %2 = linjenr.';
        MockTagTok: Label 'MOCK-%1', Locked = true, Comment = '%1 = forsendelsesnr.';
        MockTrackingUrlTok: Label 'https://tracking.example/%1', Locked = true, Comment = '%1 = sporingsnr.';
        MockLabelTok: Label 'JVBERi0xLjcK', Locked = true;

    procedure Reset()
    begin
        CreateCount := 0;
        TransmitCount := 0;
        DeleteCount := 0;
        CreateFailureText := '';
    end;

    /// <summary>
    /// Opprettelser feiler med denne meldingen til Reset kalles.
    /// </summary>
    procedure SetCreateFailure(NewErrorText: Text)
    begin
        CreateFailureText := NewErrorText;
    end;

    procedure GetCreateCount(): Integer
    begin
        exit(CreateCount);
    end;

    procedure GetTransmitCount(): Integer
    begin
        exit(TransmitCount);
    end;

    procedure GetDeleteCount(): Integer
    begin
        exit(DeleteCount);
    end;

    procedure GetDisplayName(): Text
    begin
        exit(DisplayNameLbl);
    end;

    procedure TestConnection(var ErrorText: Text): Boolean
    begin
        ErrorText := '';
        exit(true);
    end;

    procedure ValidateShipment(ShipmentHeader: Record "nShift Shipment Header KBS"; var ErrorText: Text): Boolean
    begin
        ErrorText := '';
        exit(true);
    end;

    procedure CreateShipment(var ShipmentHeader: Record "nShift Shipment Header KBS"; LabelFormat: Enum "nShift Label Format KBS"; var LabelBuffer: Record "nShift Label Buffer KBS"; var ErrorText: Text): Boolean
    var
        Package: Record "nShift Package KBS";
    begin
        ErrorText := CreateFailureText;
        if ErrorText <> '' then
            exit(false);
        CreateCount += 1;
        ShipmentHeader."nShift Shipment Tag" := StrSubstNo(MockTagTok, ShipmentHeader."No.");
        ShipmentHeader."nShift ShpCSID" := 1;
        ShipmentHeader."Tracking No." := ShipmentHeader."No.";
        Package.SetRange("Shipment No.", ShipmentHeader."No.");
        if Package.FindSet() then
            repeat
                Package."Package Tracking No." := StrSubstNo(PackageTrackingNoTok, ShipmentHeader."No.", Package."Line No.");
                Package.Modify();
                AddLabel(LabelBuffer, ShipmentHeader."No.", Package."Package Tracking No.", LabelFormat);
            until Package.Next() = 0;
        exit(true);
    end;

    procedure TransmitShipments(var ShipmentHeader: Record "nShift Shipment Header KBS"; var ErrorText: Text): Boolean
    begin
        ErrorText := '';
        TransmitCount += 1;
        exit(true);
    end;

    procedure DeleteShipment(ShipmentHeader: Record "nShift Shipment Header KBS"; var ErrorText: Text): Boolean
    begin
        ErrorText := '';
        DeleteCount += 1;
        exit(true);
    end;

    procedure RefreshShipment(var ShipmentHeader: Record "nShift Shipment Header KBS"; var ErrorText: Text): Boolean
    begin
        ErrorText := '';
        exit(true);
    end;

    procedure ReprintLabels(ShipmentHeader: Record "nShift Shipment Header KBS"; LabelFormat: Enum "nShift Label Format KBS"; var LabelBuffer: Record "nShift Label Buffer KBS"; var ErrorText: Text): Boolean
    begin
        ErrorText := '';
        AddLabel(LabelBuffer, ShipmentHeader."No.", ShipmentHeader."Tracking No.", LabelFormat);
        exit(true);
    end;

    procedure GetTrackingUrl(var ShipmentHeader: Record "nShift Shipment Header KBS"; var ErrorText: Text): Boolean
    begin
        ErrorText := '';
        ShipmentHeader."Tracking URL" := StrSubstNo(MockTrackingUrlTok, ShipmentHeader."Tracking No.");
        exit(true);
    end;

    procedure GetPrice(ShipmentHeader: Record "nShift Shipment Header KBS"; var Price: Decimal; var ErrorText: Text): Boolean
    begin
        ErrorText := '';
        Price := 100;
        exit(true);
    end;

    procedure GetEstimatedPrice(ShipmentHeader: Record "nShift Shipment Header KBS"; var Package: Record "nShift Package KBS"; var Price: Decimal; var ErrorText: Text): Boolean
    begin
        ErrorText := '';
        Price := 100;
        exit(true);
    end;

    procedure GetRateOptions(ShipmentHeader: Record "nShift Shipment Header KBS"; var Package: Record "nShift Package KBS"; SalesOrderNo: Code[20]; var RateOption: Record "nShift Rate Option KBS"; var ErrorText: Text): Boolean
    begin
        ErrorText := '';
        exit(true);
    end;

    procedure GetServicePoints(ShipmentHeader: Record "nShift Shipment Header KBS"; var Package: Record "nShift Package KBS"; var ServicePointBuffer: Record "nShift Service Point Buf. KBS"; var ErrorText: Text): Boolean
    begin
        ErrorText := '';
        exit(true);
    end;

    procedure ImportMasterData(var ImportedCount: Integer; var ErrorText: Text): Boolean
    begin
        ErrorText := '';
        ImportedCount := 0;
        exit(true);
    end;

    procedure GetSenderAddress(var LocationSetup: Record "nShift Location Setup KBS"; var ErrorText: Text): Boolean
    begin
        ErrorText := '';
        LocationSetup."Sender Name" := DisplayNameLbl;
        exit(true);
    end;

    local procedure AddLabel(var LabelBuffer: Record "nShift Label Buffer KBS"; ShipmentNo: Code[20]; PackageTrackingNo: Text[100]; LabelFormat: Enum "nShift Label Format KBS")
    var
        EntryNo: Integer;
    begin
        LabelBuffer.Reset();
        if LabelBuffer.FindLast() then
            EntryNo := LabelBuffer."Entry No.";
        LabelBuffer.Init();
        LabelBuffer."Entry No." := EntryNo + 1;
        LabelBuffer."Shipment No." := ShipmentNo;
        LabelBuffer."Package Tracking No." := PackageTrackingNo;
        LabelBuffer.Format := LabelFormat;
        LabelBuffer.Copies := 1;
        LabelBuffer.SetContentBase64(MockLabelTok);
        LabelBuffer.Insert();
    end;
}
