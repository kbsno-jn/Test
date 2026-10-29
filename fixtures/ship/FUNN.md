# Funn fra fixtures – nShift Ship (TASKS 2.1.4)

Tatt opp med `scripts/Capture-ShipFixtures.ps1` mot Actor 13131 «TEST-BC BB» (test mode) på **produksjon** `https://restapi.shipmentserver.com`.
`_index.json` har status, tid og størrelse per kall.

## Autentisering
- nShift Portal API-klient: OAuth2 client credentials mot `https://account.nshiftportal.com/idp/connect/token` (`client_secret_post`).
- Token: JWT, `expires_in` 3600 s, scope `public_api_portal_shipment_data public_api_shipmentserver` uten at scope sendes.
- Sendes som `Authorization: Bearer <token>`. Basic med Actor/nøkkel virker ikke for denne klienten.
- Samme IdP for test og prod; demo-serveren (`demo.shipmentserver.com:8080`) kjenner ikke Actor 13131 → «test-Actor» = Actor i test mode på prod-serveren.

## Feilformat (alle statuser)
```json
{ "ErrorType": "...", "Message": "...", "Errors": [ { "shipmentKind": "1", "level": "Shipment", "message": "[#000000120] ...", "fieldName": "Services", "groupName": "General" } ], "Log": [...], "CorrelationID": "guid" }
```
- 401: `ErrorType` «Unauthorized», ingen Content-Type, ingen CorrelationID.
- 404: brukes også for «Cannot find actor with ID …» og «No Shipping Rules defined» (`/shipAdvises`).
- 422: `Message` «Shipment validation failed» – detaljene ligger i `Errors[].message` (kan være tom liste!). Andre 422: «DropPoint selection not supported for this product.»
- `CorrelationID` bør lagres i API Log og vises i feilmelding.

## Respons generelt
- `Content-Type: application/json`, UTF-8 (æøå korrekt).
- JSON-tall er inkonsekvente: `products` gir tall, `stacks` gir strenger (`"StackCSID":"113116"`) og blander (`"CarrierConceptID":0` vs `"39"`). Parser må tåle begge.

## Masterdata
- `products`: `Carriers[].Subcarriers[].Products[]` med `ProdConceptID`, `ProdCSID`, `ProdName`, `GoodsTypes[]`, `Services[]` (`ServiceID`, `ServiceName`, `ServiceCode`, `GroupID`, `Kind`), `SupportsDropPoint`, `PriceCalculation.Enabled`.
- Noen produkter mangler `ProdConceptID` (H.R Olsen, Fraktbrev – egendefinerte transportører); i `/checkout` vises de som `ProdConceptID: -1`. → **Carrier Service må nøkles på `ProdCSID`**, ikke bare `ProdConceptID`.
- `GroupID` på tjenester = gjensidig utelukkende gruppe (f.eks. Incoterms, betaler). DSV krever én Incoterm-tjeneste (#000000120).
- `PriceCalculation` finnes kun for Bring (Subcarrier «Bring Norway Domestic»), ikke DSV – men se «Pris» under.
- `senderAddress`: ett adresseobjekt (`Kind` 2) – Saferoad B.Berntsen AS, Hønefoss.
- `stacks`: per transportør/subcarrier, `StackCSID` som streng.

## Fraktalternativer
- `/checkout` godtar både tall og strenger (likt resultat, 10 produkter). Velg **tall** i mapperen.
- `/checkout` med `options.Price = 1` returnerte **ingen prisfelt** (kun `ProdConceptID`, `ProdCSID`, `ProdName`, `Token`, `SupportsDropPoint`, `ShippingRulesID`). Pris må hentes via `/shipmentPrices` per produkt. **Verifiser** med Bring-produkt.
- `/shipAdvises` krever shipping rules i nShift (404 uten) → oppsettsvalg 4.2.3 er bare relevant hvis kunden lager regler.

## Enheter
- **Vekt i gram bekreftet**: `PkgWeight` 12500 → «Validation OK»; 99999999 → «Maximum weight per product cannot exceed 35 kg» (Bring 3578). Mål (cm) og volum (cm³) gjenstår å bekrefte på etikett/GET.

## Pris (`/shipmentPrices`, Bring 3578)
- **HTTP 200 selv når prisberegning feiler.** Respons: `ListPrice`, `Price1`, `Price2`, `Currency`, `Currency2`, `StatusCode`, `StatusMsg`, `Response` (base64 HTML).
- Mottatt `StatusCode: 19`, alle priser 0, HTML: «Calculation is not valid … Calculation is deactivated.» → API-klienten må sjekke `StatusCode` (≠ suksess) og dekode `Response` til feilmelding.
- `products` viser `PriceCalculation.Enabled: 1` for Bring, men `AccountNumberValue` er tom – sannsynlig årsak. **[!] Beslutning M (prisberegning aktivert) holder ikke for Actor 13131.**
- Suksessverdien for `StatusCode` og betydningen av `Currency` (int) er ukjent til vi får en vellykket pris.

## Hentesteder (`/dropPoints`, Bring 3581)
- Uten tjeneste: 422 «Cannot use DropPoint service, conditions not met.» Krever hentested-tjeneste (`Kind` 12, `RefreshDropPoint` 1), f.eks. 442123 «Valgfritt hentested». → Ta med `-DropPointServices 442123`.
- (DSV 400: 422 «DropPoint selection not supported for this product.» – bruk `SupportsDropPoint`.)

## Validering
- `/shipmentValidations` OK: `{"Messages":["Validation OK"]}` (200). Feil: 422 med `Errors[]` (`fieldName`, `groupName`, `level`, `message`).

## Opprett forsendelse (`POST /shipments`, Bring 3578, `Visibility=extended`)
- 201. **Identifikator heter `ShpTag`** (ikke `ShipmentTag` som i planen/Swagger-tekst) – brukes i `/shipments/{shipmentTag}`. `ShpCSID` (int) brukes i `labelReprint`.
- Sendingsnr. `ShpNo`, kolli: `Lines[].LineTag`/`LineCSID`, `Lines[].Pkgs[].PkgTag`/`PkgCSID`/`PkgNo` (kollinr./SSCC).
- Etikett: `Labels[].Content` (base64 PDF), `Type` (4 = PDF), `PkgNo`, `PkgTag`, `DocumentName`.
- Ekstra info: `PayerAccountAtCarrier`, `StackCSID`, `CarriagePayer`, `References` Kind 56 / Lines.References Kind 52 «weightU15» lagt til av nShift.
- **Ingen prisfelt** i extended-respons (prisberegning deaktivert – verifiser igjen når aktivert).
- Postnr. «0000» ble **opprettet (201) med vanlig Bring-etikett** – ingen feil-etikett, ingen advarsel. → BC må validere postnr./adresse selv før opprettelse. «201 med feil-etikett» ble ikke reprodusert; parseren bør likevel sjekke at `Labels[]` finnes og at `ShpNo` er satt.
- Vekt 99 999 999 g → 422 (samme melding som validering).
- **Enheter bekreftet**: vekt gram, mål cm (`Lines[]` 60/40/40 som sendt), volum cm³ (96000). Merk: hode-feltene `Height/Length/Width` = 45 i responsen er ikke våre verdier – bruk linjenivå.
- Etikettformat: `Labels[].Type` 4 = PDF, 10 = PNG (816 × 1536 px, 203 dpi = 102 × 192 mm), 13 = ZPLGK (base64 av rå ZPL, starter med `~DGR:` grafikk-nedlasting). Én etikett per kolli (`PkgNo`).

## Andre kall
- `GET /shipments/{ShpTag}`: samme struktur som opprett-responsen, uten `Labels`. Ingen pris.
- `GET /shipments/{ShpTag}/trackingURL`: `{ "TrackingURL": "...", "Pkgs": [ { "PkgNo", "TrackingURL" } ] }` – sending- og kollinivå (http, ikke https).
- `POST /shipments/labelReprint` `{data:{ShpCSID}, options:{Labels:"PDF"}}` → `{ "Labels": [ ...samme som ved opprett... ] }`.
- `DELETE /shipments/{ShpTag}` → 200 `{ "Messages": ["Shipment <tag> has been deleted"] }`.
- `/dropPoints` (3581 + tjeneste 442123) → `{ "DropPoints": [ { "OriginalID", "RoutingCode", "Name1", "Street1", "PostCode", "City", "CountryCode", "Latitude", "Longitude", "Distance" (km), "DropPointType", "OpeningHours": [ {Day, Open, Close} ] } ] }`. `OriginalID` → `AgentNo` ved opprettelse.

## Ikke tatt opp
- `PUT /shipments/manifest` – ville overført til transportør i prod. Bygges fra Swagger-eksempel `{"data":{"ShipmentTags":["<ShpTag>"]},"options":{}}`; verifiseres ved første reelle overføring.
- Vellykket `/shipmentPrices` og pris i `Visibility=extended` – krever at prisberegning aktiveres (TASKS 2.1.6).
- 201 med feil-etikett – ikke reprodusert.
- `manifest` kan ikke tas opp i prod (overfører til transportør) – bygges fra Swagger-eksempel.
