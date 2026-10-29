namespace Knowit.nShift.Test;

using Knowit.nShift;

/// <summary>
/// Svarer på HTTP-kall fra «nShift API Client KBS» i stedet for nShift. Bindes med BindSubscription i testen.
/// Token-kall gjenkjennes på token-URL-en; Ship-kall får svarene i køen (standard 200).
/// </summary>
codeunit 73966 "nShift HTTP Mock KBS"
{
    EventSubscriberInstance = Manual;

    var
        ShipStatuses: List of [Integer];
        ShipBodies: List of [Text];
        TokenUrl: Text;
        TokenStatus: Integer;
        TokenBody: Text;
        TokenCalls: Integer;
        ShipCalls: Integer;
        LastShipUrl: Text;
        LastShipMethod: Text;
        LastShipRequestBody: Text;
        ShipRequests: List of [Text];

    procedure Initialize(NewTokenUrl: Text; NewTokenStatus: Integer; NewTokenBody: Text)
    begin
        Clear(ShipStatuses);
        Clear(ShipBodies);
        TokenUrl := NewTokenUrl;
        TokenStatus := NewTokenStatus;
        TokenBody := NewTokenBody;
        TokenCalls := 0;
        ShipCalls := 0;
        LastShipUrl := '';
        LastShipMethod := '';
        LastShipRequestBody := '';
        Clear(ShipRequests);
    end;

    /// <summary>
    /// Ship-kall nr. Index (1-basert) som «METODE URL», f.eks. «DELETE https://ship.example/ShipServer/13131/shipments/TAG».
    /// </summary>
    procedure GetShipRequest(Index: Integer): Text
    begin
        if Index > ShipRequests.Count() then
            exit('');
        exit(ShipRequests.Get(Index));
    end;

    /// <summary>
    /// Legger til neste svar fra nShift Ship.
    /// </summary>
    procedure EnqueueShipResponse(Status: Integer; Body: Text)
    begin
        ShipStatuses.Add(Status);
        ShipBodies.Add(Body);
    end;

    procedure GetTokenCalls(): Integer
    begin
        exit(TokenCalls);
    end;

    procedure GetShipCalls(): Integer
    begin
        exit(ShipCalls);
    end;

    procedure GetLastShipUrl(): Text
    begin
        exit(LastShipUrl);
    end;

    procedure GetLastShipMethod(): Text
    begin
        exit(LastShipMethod);
    end;

    procedure GetLastShipRequestBody(): Text
    begin
        exit(LastShipRequestBody);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"nShift API Client KBS", OnBeforeSendHttp, '', false, false)]
    local procedure HandleSendHttp(Method: Text; Url: Text; RequestBody: Text; var StatusCode: Integer; var ResponseText: Text; var Handled: Boolean)
    begin
        Handled := true;
        if Url = TokenUrl then begin
            TokenCalls += 1;
            StatusCode := TokenStatus;
            ResponseText := TokenBody;
            exit;
        end;
        ShipCalls += 1;
        LastShipUrl := Url;
        LastShipMethod := Method;
        LastShipRequestBody := RequestBody;
        ShipRequests.Add(Method + ' ' + Url);
        StatusCode := 200;
        ResponseText := '';
        if ShipStatuses.Count() > 0 then begin
            StatusCode := ShipStatuses.Get(1);
            ResponseText := ShipBodies.Get(1);
            ShipStatuses.RemoveAt(1);
            ShipBodies.RemoveAt(1);
        end;
    end;
}
