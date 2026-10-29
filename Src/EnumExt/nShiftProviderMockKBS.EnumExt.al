namespace Knowit.nShift.Test;

using Knowit.nShift;

enumextension 73960 "nShift Provider Mock KBS" extends "nShift Provider KBS"
{
    value(73960; "Mock KBS")
    {
        Caption = 'Mock (kun test)';
        Implementation = "nShift ICarrier Provider KBS" = "nShift Provider Mock KBS";
    }
}
