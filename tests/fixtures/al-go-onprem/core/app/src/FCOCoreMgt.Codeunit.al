codeunit 50100 "FCO Core Mgt."
{
    Access = Public;

    procedure GetRegionCode(): Code[10]
    begin
        exit('DEFAULT');
    end;
}
