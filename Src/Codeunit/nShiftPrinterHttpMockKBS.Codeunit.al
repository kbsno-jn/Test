namespace Knowit.nShift.Test;

using Knowit.nShift;

/// <summary>
/// Svarer på HTTP-kall fra «nShift Printer HTTP KBS» (PrintNode) i stedet for tjenesten. Bindes med BindSubscription.
/// </summary>
codeunit 73972 "nShift Printer Http Mock KBS"
{
    EventSubscriberInstance = Manual;

    var
        ResponseStatus: Integer;
        ResponseBody: Text;
        CallCount: Integer;
        LastMethod: Text;
        LastUrl: Text;
        LastRequestBody: Text;

    procedure Initialize(Status: Integer; Body: Text)
    begin
        ResponseStatus := Status;
        ResponseBody := Body;
        CallCount := 0;
        LastMethod := '';
        LastUrl := '';
        LastRequestBody := '';
    end;

    procedure GetCallCount(): Integer
    begin
        exit(CallCount);
    end;

    procedure GetLastMethod(): Text
    begin
        exit(LastMethod);
    end;

    procedure GetLastUrl(): Text
    begin
        exit(LastUrl);
    end;

    procedure GetLastRequestBody(): Text
    begin
        exit(LastRequestBody);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"nShift Printer HTTP KBS", OnBeforeSendHttp, '', false, false)]
    local procedure HandleSendHttp(Method: Text; Url: Text; RequestBody: Text; var StatusCode: Integer; var ResponseText: Text; var Handled: Boolean)
    begin
        Handled := true;
        CallCount += 1;
        LastMethod := Method;
        LastUrl := Url;
        LastRequestBody := RequestBody;
        StatusCode := ResponseStatus;
        ResponseText := ResponseBody;
    end;
}
