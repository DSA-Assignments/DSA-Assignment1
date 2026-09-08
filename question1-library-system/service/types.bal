// Shared data models for the Library & Resource Management System.
// NOTE: Person 1 (Setup & Data Lead) and Person 3 (Maintenance & Components)
// also read/write these same types - coordinate before changing field names.

public type Task record {|
    string taskId;
    string description;
    boolean completed = false;
|};

public type WorkOrder record {|
    string orderId;
    string status; // OPEN, IN_PROGRESS, CLOSED
    string description;
    Task[] tasks = [];
|};

public type ScheduleItem record {|
    string scheduleId;
    string 'type; // MAINTENANCE, BOOKING
    string dueDate; // YYYY-MM-DD
    string description;
|};

public type Component record {|
    string compId;
    string name;
    string description;
|};

public type Asset record {|
    string assetTag;
    string name;
    string description;
    string institution;
    string site;
    string status; // AVAILABLE, LOANED_OUT, OCCUPIED, UNDER_MAINTENANCE, DISPOSED
    string dateAcquired; // YYYY-MM-DD
    Component[] components = [];
    ScheduleItem[] schedules = [];
    WorkOrder[] workOrders = [];
|};

// Single source of truth for all assets, keyed by assetTag.
// Every read/write goes through a `lock` block since http:Service resources
// can run on concurrent strands.
isolated table<Asset> key(assetTag) assetTable = table [];
