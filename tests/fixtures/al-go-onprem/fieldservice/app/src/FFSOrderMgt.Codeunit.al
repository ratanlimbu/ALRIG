codeunit 50201 "FFS Order Mgt."
{
    procedure AssignRegion(var ServiceOrder: Record "FFS Service Order")
    var
        CoreMgt: Codeunit "FCO Core Mgt.";
    begin
        ServiceOrder."Region Code" := CoreMgt.GetRegionCode();
        ServiceOrder.Modify(true);
    end;
}
