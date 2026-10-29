namespace Knowit.nShift.Test;

/// <summary>
/// Enkle assert-hjelpere, slik at testappen ikke trenger Microsofts testbiblioteker for å kompilere.
/// </summary>
codeunit 73961 "nShift Library Assert KBS"
{
    var
        AreEqualErr: Label 'Forventet <%1>, faktisk <%2>. %3', Comment = '%1 = forventet verdi, %2 = faktisk verdi, %3 = beskrivelse av kontrollen';
        IsTrueErr: Label 'Forventet sann. %1', Comment = '%1 = beskrivelse av kontrollen';
        IsFalseErr: Label 'Forventet usann. %1', Comment = '%1 = beskrivelse av kontrollen';

    procedure AreEqual(Expected: Variant; Actual: Variant; Context: Text)
    begin
        if Format(Expected, 0, 9) <> Format(Actual, 0, 9) then
            Error(AreEqualErr, Format(Expected, 0, 9), Format(Actual, 0, 9), Context);
    end;

    procedure IsTrue(Condition: Boolean; Context: Text)
    begin
        if not Condition then
            Error(IsTrueErr, Context);
    end;

    procedure IsFalse(Condition: Boolean; Context: Text)
    begin
        if Condition then
            Error(IsFalseErr, Context);
    end;
}
