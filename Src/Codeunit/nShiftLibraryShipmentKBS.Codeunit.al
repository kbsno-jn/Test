namespace Knowit.nShift.Test;

using Knowit.nShift;
using Microsoft.Foundation.Address;
using Microsoft.Foundation.Company;
using Microsoft.Inventory.Location;

/// <summary>
/// Testdata for forsendelser. Forsendelsen speiler FIXTURE-PDF fra opptaket mot nShift (Bring 3578, 12,5 kg, 60 × 40 × 40 cm),
/// slik at JSON-en kan sammenlignes med requesten nShift godtok.
/// </summary>
codeunit 73968 "nShift Library Shipment KBS"
{
    var
        LocationCodeTok: Label 'NSH-TEST', Locked = true;
        CarrierServiceCodeTok: Label 'BRING-PAKKE', Locked = true;
        TokenUrlTok: Label 'https://idp.example/connect/token', Locked = true;
        TokenJsonTok: Label '{"access_token":"tok","expires_in":3600}', Locked = true;

    procedure GetCarrierServiceCode(): Code[20]
    begin
        exit(CarrierServiceCodeTok);
    end;

    /// <summary>
    /// Oppretter forsendelsen ShipmentNo med ett kolli (linje 10000) og alt oppsett den trenger.
    /// </summary>
    procedure CreateShipment(var ShipmentHeader: Record "nShift Shipment Header KBS"; ShipmentNo: Code[20])
    var
        Setup: Record "nShift Setup KBS";
        CarrierService: Record "nShift Carrier Service KBS";
        LocationSetup: Record "nShift Location Setup KBS";
        Package: Record "nShift Package KBS";
        Location: Record Location;
    begin
        EnsureCountryNo();
        Setup.GetRecordOnce();
        Setup."Weight Factor" := 1000;
        Setup."Volume Factor" := 1000000;
        Setup.Modify();

        Location.Init();
        Location.Code := LocationCodeTok;
        if not Location.Insert() then;
        LocationSetup.Init();
        LocationSetup."Location Code" := LocationCodeTok;
        LocationSetup."Sender Name" := 'Testavsender AS';
        LocationSetup."Sender Address" := 'Lagerveien 5';
        LocationSetup."Sender Post Code" := '1830';
        LocationSetup."Sender City" := 'ASKIM';
        LocationSetup."Sender Country/Region Code" := 'NO';
        LocationSetup."Sender Phone No." := '+4769000000';
        if not LocationSetup.Insert() then
            LocationSetup.Modify();

        CarrierService.Init();
        CarrierService.Code := CarrierServiceCodeTok;
        CarrierService.Description := 'Bring Pakke til bedrift';
        CarrierService."Prod Concept ID" := 3578;
        if not CarrierService.Insert() then
            CarrierService.Modify();

        ShipmentHeader.Init();
        ShipmentHeader."No." := ShipmentNo;
        ShipmentHeader."Sales Order No." := 'FIXTURE-PDF';
        ShipmentHeader."Location Code" := LocationCodeTok;
        ShipmentHeader."Carrier Service Code" := CarrierServiceCodeTok;
        ShipmentHeader."Customer No." := 'K10000';
        ShipmentHeader."Ship-to Name" := 'Testkunde AS';
        ShipmentHeader."Ship-to Address" := 'Storgata 1';
        ShipmentHeader."Ship-to Post Code" := '0155';
        ShipmentHeader."Ship-to City" := 'OSLO';
        ShipmentHeader."Ship-to Country/Region Code" := 'NO';
        ShipmentHeader."Ship-to Contact" := 'Ola Nordmann';
        ShipmentHeader."Ship-to Mobile Phone No." := '+4790000000';
        ShipmentHeader."Ship-to E-Mail" := 'test@example.no';
        ShipmentHeader."Delivery Instructions" := 'Lever ved varemottak';
        ShipmentHeader.Insert();

        InsertPackage(ShipmentHeader."No.", 10000, 12.5);
        Package.Get(ShipmentHeader."No.", 10000);
        Package."Contents Description" := 'Reservedeler';
        Package.Modify();
    end;

    /// <summary>
    /// Fjerner pakkebord fra brukeroppsettet til testbrukeren og fra testlokasjonen, så testen ikke påvirkes av
    /// oppsett i sandkassen. Bruk bare i tester med AutoRollback – med AutoCommit blir brukerens oppsett slettet.
    /// </summary>
    procedure ClearPackingStationDefaults()
    var
        UserSetup: Record "nShift User Setup KBS";
        LocationSetup: Record "nShift Location Setup KBS";
    begin
        if UserSetup.Get(CopyStr(UserId(), 1, MaxStrLen(UserSetup."User ID"))) then
            UserSetup.Delete();
        if LocationSetup.Get(LocationCodeTok) then begin
            LocationSetup."Default Packing Station Code" := '';
            LocationSetup.Modify();
        end;
    end;

    procedure InsertPackage(ShipmentNo: Code[20]; LineNo: Integer; WeightKg: Decimal)
    var
        Package: Record "nShift Package KBS";
    begin
        Package.Init();
        Package."Shipment No." := ShipmentNo;
        Package."Line No." := LineNo;
        Package."Weight (kg)" := WeightKg;
        Package.Validate("Length (cm)", 60);
        Package.Validate("Width (cm)", 40);
        Package.Validate("Height (cm)", 40);
        Package.Insert();
    end;

    /// <summary>
    /// Setter opp tilkobling mot eksempel-URL-er og binder HTTP-mocken, så ingen kall går til nShift.
    /// Token-kallet svarer alltid OK; Ship-svar legges i køen med HttpMock.EnqueueShipResponse.
    /// </summary>
    procedure InitializeHttpMock(var HttpMock: Codeunit "nShift HTTP Mock KBS")
    var
        Setup: Record "nShift Setup KBS";
        SecretMgt: Codeunit "nShift Secret Mgt. KBS";
    begin
        HttpMock.Initialize(TokenUrlTok, 200, TokenJsonTok);
        BindSubscription(HttpMock);
        Setup.GetRecordOnce();
        Setup.Provider := Setup.Provider::Ship;
        Setup."Base URL" := 'https://ship.example';
        Setup."Token URL" := TokenUrlTok;
        Setup."Actor ID" := 13131;
        Setup."Client ID" := 'cc_test';
        Setup.Modify();
        SecretMgt.SetShipClientSecretFormEncoded(SecretStrSubstNo('secret'));
        SecretMgt.ClearShipAccessToken();
    end;

    local procedure EnsureCountryNo()
    var
        CountryRegion: Record "Country/Region";
        CompanyInformation: Record "Company Information";
    begin
        if not CountryRegion.Get('NO') then begin
            CountryRegion.Init();
            CountryRegion.Code := 'NO';
            CountryRegion.Insert();
        end;
        CountryRegion."ISO Code" := 'NO';
        CountryRegion.Modify();
        if not CompanyInformation.Get() then
            CompanyInformation.Insert();
        CompanyInformation."Country/Region Code" := 'NO';
        CompanyInformation.Modify();
    end;
}
