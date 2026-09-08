import ballerina/io;
import ballerina/http;

// Task 4 (client half): Ballerina command-line client for the library service.
// Menu items 4 & 5 call endpoints owned by Person 3 (maintenance/schedules) —
// point BASE_URL at the running service and make sure their endpoints exist
// before demoing those two options.

final http:Client libraryClient = check new ("http://localhost:8080/library");

public function main() returns error? {
    boolean running = true;
    while running {
        io:println("\n=== Library & Resource Management ===");
        io:println("1. Loan / return an asset");
        io:println("2. Global view (all assets)");
        io:println("3. Campus view (by institution / site)");
        io:println("4. Overdue dashboard");
        io:println("5. Schedule manager");
        io:println("6. Exit");
        string choice = io:readln("Choose an option: ");

        error? result = ();
        if choice == "1" {
            result = loanOrReturn();
        } else if choice == "2" {
            result = globalView();
        } else if choice == "3" {
            result = campusView();
        } else if choice == "4" {
            result = overdueDashboard();
        } else if choice == "5" {
            result = scheduleManager();
        } else if choice == "6" {
            running = false;
        } else {
            io:println("Invalid option.");
        }

        if result is error {
            io:println("Error: ", result.message());
        }
    }
}

function loanOrReturn() returns error? {
    string tag = io:readln("Asset tag: ");
    string status = io:readln("New status (AVAILABLE / LOANED_OUT / OCCUPIED): ");

    json current = check libraryClient->get("/assets/" + tag);
    map<json> updated = <map<json>>current.clone();
    updated["status"] = status;

    http:Response resp = check libraryClient->put("/assets/" + tag, updated);
    io:println("Updated. Status code: ", resp.statusCode);
}

function globalView() returns error? {
    json assets = check libraryClient->get("/assets");
    io:println(assets.toJsonString());
}

function campusView() returns error? {
    string institution = io:readln("Institution: ");
    string site = io:readln("Site (leave blank for all campuses of this institution): ");

    string path = site.trim().length() > 0
        ? string `/institutions/${institution}/sites/${site}/assets`
        : string `/institutions/${institution}/assets`;

    json assets = check libraryClient->get(path);
    io:println(assets.toJsonString());
}

function overdueDashboard() returns error? {
    // Assumes GET /library/assets/overdue — built by Person 3.
    json overdue = check libraryClient->get("/assets/overdue");
    io:println(overdue.toJsonString());
}

function scheduleManager() returns error? {
    // Assumes POST /library/assets/{tag}/schedules — built by Person 3.
    string tag = io:readln("Asset tag: ");
    string scheduleId = io:readln("Schedule ID: ");
    string scheduleType = io:readln("Type (MAINTENANCE / BOOKING): ");
    string dueDate = io:readln("Due date (YYYY-MM-DD): ");
    string description = io:readln("Description: ");

    json body = {
        scheduleId: scheduleId,
        'type: scheduleType,
        dueDate: dueDate,
        description: description
    };

    http:Response resp = check libraryClient->post(string `/assets/${tag}/schedules`, body);
    io:println("Status code: ", resp.statusCode);
}
