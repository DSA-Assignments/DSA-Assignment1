import ballerina/http;

// A component is a part of an asset (e.g., a printer motor)
public type Component record {
    string compId;
    string name;
    string description;
};

// A schedule is a maintenance or booking plan
public type Schedule record {
    string scheduleId;
    string scheduleType;  // "MAINTENANCE" or "BOOKING"
    string dueDate;       // Format: YYYY-MM-DD
    string description;
};

// A task is a sub-task within a work order
public type Task record {
    string taskId;
    string description;
};

// A work order is a repair request
public type WorkOrder record {
    string orderId;
    string orderStatus;   // "OPEN" or "CLOSED"
    string description;
    Task[] tasks;         // List of sub-tasks
};

// An Asset is the main record for any library resource
public type Asset record {
    string assetTag;
    string name;
    string description;
    string institution;
    string site;
    string assetStatus;   // AVAILABLE, LOANED_OUT, UNDER_MAINTENANCE, DISPOSED
    string dateAcquired;
    Component[] components;
    Schedule[] schedules;
    WorkOrder[] workOrders;
};

// ===== DATABASE =====
// This is where we store all assets
// The key is the assetTag, the value is the full Asset record
map<Asset> assetDatabase = {};


// ===== INSTITUTION DATABASE =====
// Store list of institutions
string[] institutionList = [];



// Helper function to validate date format (YYYY-MM-DD)
function isValidDate(string dateStr) returns boolean {
    // Check length (10 characters: YYYY-MM-DD)
    if dateStr.length() != 10 {
        return false;
    }
    // Check that positions 4 and 7 are dashes
    if dateStr.substring(4, 5) != "-" || dateStr.substring(7, 8) != "-" {
        return false;
    }
    // Check that all other characters are digits
    foreach int i in 0 ..< dateStr.length() {
        if i == 4 || i == 7 {
            continue; // Skip dashes
        }
        string char = dateStr.substring(i, i + 1);
        if char < "0" || char > "9" {
            return false;
        }
    }
    return true;
}



// Helper function to check if an asset is a room or lab
function isRoomOrLab(string assetTag) returns boolean {
    // Check if the asset tag contains "ROOM" or "LAB"
    if assetTag.includes("ROOM") || assetTag.includes("LAB") {
        return true;
    }
    return false;
}

// ===== API SERVICE =====
@http:ServiceConfig {
    cors: {
        allowOrigins: ["*"],
        allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        allowHeaders: ["Content-Type"],
        maxAge: 3600
    }
}
service /library on new http:Listener(9090) {

   // Health check - tests if API is running
    resource function get health() returns string {
        return "Library API is running!";
    }



    // CREATE: Add a new asset
    resource function post assets(Asset newAsset) returns json|http:BadRequest {
        // Step 1: Check if this assetTag already exists
        if assetDatabase.hasKey(newAsset.assetTag) {
            return http:BAD_REQUEST;
        }
        // Step 2: Save the asset in the database
        assetDatabase[newAsset.assetTag] = newAsset;
        // Step 3: Return success message
        return {
            message: "Asset created successfully",
            assetTag: newAsset.assetTag
        };
    }


    // READ ALL: Get all assets
    resource function get assets() returns Asset[] {
        // Step 1: Create an empty list
        Asset[] allAssets = [];
        // Step 2: Loop through every asset in the database
        foreach string key in assetDatabase.keys() {
            Asset? asset = assetDatabase[key];
            if asset is Asset {
                allAssets.push(asset);
            }
        }
        // Step 3: Return the list
        return allAssets;
    }

    // READ ONE: Get a specific asset by assetTag
    resource function get assets/[string assetTag]() returns Asset|http:NotFound {
        Asset? asset = assetDatabase[assetTag];
        if asset is Asset {
            return asset;
        }
        return http:NOT_FOUND;
    }



           // UPDATE: Change an existing asset
    resource function put assets/[string assetTag](Asset updatedAsset) returns json|http:NotFound|http:BadRequest {
        if !assetDatabase.hasKey(assetTag) {
            return http:NOT_FOUND;
        }
        if assetTag != updatedAsset.assetTag {
            return http:BAD_REQUEST;
        }
        // Get the current asset to check its status
        Asset? current = assetDatabase[assetTag];
        if current is Asset {
            // If trying to LOAN, only allow if currently AVAILABLE
            if updatedAsset.assetStatus == "LOANED_OUT" && current.assetStatus != "AVAILABLE" {
                return http:BAD_REQUEST;
            }
            // If trying to BOOK, only allow if:
            // 1. Currently AVAILABLE
            // 2. Asset is a ROOM or LAB (not a book/laptop)
            if updatedAsset.assetStatus == "OCCUPIED" {
                if current.assetStatus != "AVAILABLE" {
                    return http:BAD_REQUEST;
                }
                // Check if the asset is a room or lab
                if !isRoomOrLab(assetTag) {
                    return http:BAD_REQUEST;
                }
            }
        }
        assetDatabase[assetTag] = updatedAsset;
        return {
            message: "Asset updated successfully",
            assetTag: assetTag
        };
    }

    // DELETE: Remove an asset
    resource function delete assets/[string assetTag]() returns json|http:NotFound {
        // Step 1: Check if the asset exists
        if !assetDatabase.hasKey(assetTag) {
            return http:NOT_FOUND;
        }
        // Step 2: Remove it from the database
        _ = assetDatabase.remove(assetTag);
        // Step 3: Return success
        return {
            message: "Asset deleted successfully",
            assetTag: assetTag
        };
    }

    // FILTER BY INSTITUTION: Get assets by institution
    resource function get assets/institution/[string institution]() returns Asset[] {
        Asset[] result = [];
        foreach string key in assetDatabase.keys() {
            Asset? asset = assetDatabase[key];
            if asset is Asset && asset.institution == institution {
                result.push(asset);
            }
        }
        return result;
    }


    // FILTER BY SITE: Get assets by campus
    resource function get assets/site/[string site]() returns Asset[] {
        Asset[] result = [];
        foreach string key in assetDatabase.keys() {
            Asset? asset = assetDatabase[key];
            if asset is Asset && asset.site == site {
                result.push(asset);
            }
        }
        return result;
    }



    // OVERDUE MAINTENANCE: Find assets with passed maintenance dates
    resource function get assets/overdue() returns json {
        // Today's date (you can change this to test)
        string today = "2026-09-10";
        json[] overdue = [];
        
        foreach string key in assetDatabase.keys() {
            Asset? asset = assetDatabase[key];
            if asset is Asset {
                foreach Schedule schedule in asset.schedules {
                    if schedule.scheduleType == "MAINTENANCE" && schedule.dueDate < today {
                        overdue.push({
                            assetTag: asset.assetTag,
                            name: asset.name,
                            dueDate: schedule.dueDate,
                            description: schedule.description
                        });
                    }
                }
            }
        }
        return overdue;
    }

           // ADD SCHEDULE: Add a schedule to an asset
    resource function post assets/[string assetTag]/schedules(Schedule newSchedule) returns json|http:NotFound|http:BadRequest {
        if !assetDatabase.hasKey(assetTag) {
            return http:NOT_FOUND;
        }
        // Validate date format (YYYY-MM-DD)
        if !isValidDate(newSchedule.dueDate) {
            return http:BAD_REQUEST;
        }
        Asset? existing = assetDatabase[assetTag];
        if existing is Asset {
            Schedule[] updatedSchedules = existing.schedules;
            updatedSchedules.push(newSchedule);
            Asset updatedAsset = {
                assetTag: existing.assetTag,
                name: existing.name,
                description: existing.description,
                institution: existing.institution,
                site: existing.site,
                assetStatus: existing.assetStatus,
                dateAcquired: existing.dateAcquired,
                components: existing.components,
                schedules: updatedSchedules,
                workOrders: existing.workOrders
            };
            assetDatabase[assetTag] = updatedAsset;
            return {
                message: "Schedule added successfully",
                scheduleId: newSchedule.scheduleId
            };
        }
        return http:NOT_FOUND;
    }




    // ADD WORK ORDER: Add a work order to an asset
    resource function post assets/[string assetTag]/workorders(WorkOrder newWorkOrder) returns json|http:NotFound {
        if !assetDatabase.hasKey(assetTag) {
            return http:NOT_FOUND;
        }
        Asset? existing = assetDatabase[assetTag];
        if existing is Asset {
            WorkOrder[] updatedWorkOrders = existing.workOrders;
            updatedWorkOrders.push(newWorkOrder);
            Asset updatedAsset = {
                assetTag: existing.assetTag,
                name: existing.name,
                description: existing.description,
                institution: existing.institution,
                site: existing.site,
                assetStatus: existing.assetStatus,
                dateAcquired: existing.dateAcquired,
                components: existing.components,
                schedules: existing.schedules,
                workOrders: updatedWorkOrders
            };
            assetDatabase[assetTag] = updatedAsset;
            return {
                message: "Work order added successfully",
                orderId: newWorkOrder.orderId
            };
        }
        return http:NOT_FOUND;
    }



    // UPDATE WORK ORDER: Change work order status
    resource function put assets/[string assetTag]/workorders/[string orderId](string newStatus) returns json|http:NotFound {
        if !assetDatabase.hasKey(assetTag) {
            return http:NOT_FOUND;
        }
        Asset? existing = assetDatabase[assetTag];
        if existing is Asset {
            WorkOrder[] updatedWorkOrders = [];
            boolean found = false;
            foreach WorkOrder wo in existing.workOrders {
                if wo.orderId == orderId {
                    WorkOrder updatedWO = {
                        orderId: wo.orderId,
                        orderStatus: newStatus,
                        description: wo.description,
                        tasks: wo.tasks
                    };
                    updatedWorkOrders.push(updatedWO);
                    found = true;
                } else {
                    updatedWorkOrders.push(wo);
                }
            }
            if !found {
                return http:NOT_FOUND;
            }
            Asset updatedAsset = {
                assetTag: existing.assetTag,
                name: existing.name,
                description: existing.description,
                institution: existing.institution,
                site: existing.site,
                assetStatus: existing.assetStatus,
                dateAcquired: existing.dateAcquired,
                components: existing.components,
                schedules: existing.schedules,
                workOrders: updatedWorkOrders
            };
            assetDatabase[assetTag] = updatedAsset;
            return {
                message: "Work order updated successfully",
                orderId: orderId,
                newStatus: newStatus
            };
        }
        return http:NOT_FOUND;
    }


    // ADD COMPONENT: Add a component to an asset
    resource function post assets/[string assetTag]/components(Component newComponent) returns json|http:NotFound {
        if !assetDatabase.hasKey(assetTag) {
            return http:NOT_FOUND;
        }
        Asset? existing = assetDatabase[assetTag];
        if existing is Asset {
            Component[] updatedComponents = existing.components;
            updatedComponents.push(newComponent);
            Asset updatedAsset = {
                assetTag: existing.assetTag,
                name: existing.name,
                description: existing.description,
                institution: existing.institution,
                site: existing.site,
                assetStatus: existing.assetStatus,
                dateAcquired: existing.dateAcquired,
                components: updatedComponents,
                schedules: existing.schedules,
                workOrders: existing.workOrders
            };
            assetDatabase[assetTag] = updatedAsset;
            return {
                message: "Component added successfully",
                compId: newComponent.compId
            };
        }
        return http:NOT_FOUND;
    }


    // REMOVE COMPONENT: Remove a component from an asset
    resource function delete assets/[string assetTag]/components/[string compId]() returns json|http:NotFound {
        if !assetDatabase.hasKey(assetTag) {
            return http:NOT_FOUND;
        }
        Asset? existing = assetDatabase[assetTag];
        if existing is Asset {
            Component[] updatedComponents = [];
            boolean found = false;
            foreach Component comp in existing.components {
                if comp.compId == compId {
                    found = true;
                } else {
                    updatedComponents.push(comp);
                }
            }
            if !found {
                return http:NOT_FOUND;
            }
            Asset updatedAsset = {
                assetTag: existing.assetTag,
                name: existing.name,
                description: existing.description,
                institution: existing.institution,
                site: existing.site,
                assetStatus: existing.assetStatus,
                dateAcquired: existing.dateAcquired,
                components: updatedComponents,
                schedules: existing.schedules,
                workOrders: existing.workOrders
            };
            assetDatabase[assetTag] = updatedAsset;
            return {
                message: "Component removed successfully",
                compId: compId
            };
        }
        return http:NOT_FOUND;
    }



        // REMOVE SCHEDULE: Remove a schedule from an asset
    resource function delete assets/[string assetTag]/schedules/[string scheduleId]() returns json|http:NotFound {
        if !assetDatabase.hasKey(assetTag) {
            return http:NOT_FOUND;
        }
        Asset? existing = assetDatabase[assetTag];
        if existing is Asset {
            Schedule[] updatedSchedules = [];
            boolean found = false;
            foreach Schedule sch in existing.schedules {
                if sch.scheduleId == scheduleId {
                    found = true;
                } else {
                    updatedSchedules.push(sch);
                }
            }
            if !found {
                return http:NOT_FOUND;
            }
            Asset updatedAsset = {
                assetTag: existing.assetTag,
                name: existing.name,
                description: existing.description,
                institution: existing.institution,
                site: existing.site,
                assetStatus: existing.assetStatus,
                dateAcquired: existing.dateAcquired,
                components: existing.components,
                schedules: updatedSchedules,
                workOrders: existing.workOrders
            };
            assetDatabase[assetTag] = updatedAsset;
            return {
                message: "Schedule removed successfully",
                scheduleId: scheduleId
            };
        }
        return http:NOT_FOUND;
    }

    // ADD INSTITUTION: Add a new institution to the list
    resource function post institutions(string institutionName) returns json|http:BadRequest {
        foreach string inst in institutionList {
            if inst == institutionName {
                return http:BAD_REQUEST;
            }
        }
        institutionList.push(institutionName);
        return {
            message: "Institution added successfully",
            institution: institutionName
        };
    }

    // GET ALL INSTITUTIONS: View all institutions
    resource function get institutions() returns string[] {
        return institutionList;
    }

    // REMOVE INSTITUTION: Remove an institution from the list
    resource function delete institutions/[string institutionName]() returns json|http:NotFound {
        string[] updatedList = [];
        boolean found = false;
        foreach string inst in institutionList {
            if inst == institutionName {
                found = true;
            } else {
                updatedList.push(inst);
            }
        }
        if !found {
            return http:NOT_FOUND;
        }
        institutionList = updatedList;
        return {
            message: "Institution removed successfully",
            institution: institutionName
        };
    }



}