namespace Knowit.nShift.Test;

using Knowit.nShift;

enumextension 73961 "nShift Label Printer Mock KBS" extends "nShift Label Printer KBS"
{
    value(73960; "Mock KBS")
    {
        Caption = 'Mock-skriver (kun test)';
        Implementation = "nShift ILabel Printer KBS" = "nShift Printer Mock KBS";
    }
}
