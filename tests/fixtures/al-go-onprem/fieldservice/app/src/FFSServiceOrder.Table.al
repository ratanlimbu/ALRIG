table 50200 "FFS Service Order"
{
    DataClassification = CustomerContent;

    fields
    {
        field(1; "No."; Code[20]) { }
        field(2; "Region Code"; Code[10]) { }
    }

    keys
    {
        key(PK; "No.") { Clustered = true; }
    }
}
