import ballerina/http;

// Covers:
//  - Task 2: Asset CRUD + institution/site filtering
//  - Task 4 (part 1): Work orders & task tracking
// Maintenance/overdue checks and component/schedule endpoints (Task 3) are
// NOT in this file — see maintenance_api.bal (owned by Person 3).

service /library on new http:Listener(8080) {

    // ---------------- ASSET CRUD ----------------

    resource function post assets(@http:Payload Asset newAsset) returns Asset|http:Conflict {
        lock {
            if assetTable.hasKey(newAsset.assetTag) {
                return http:CONFLICT;
            }
            assetTable.add(newAsset.clone());
        }
        return newAsset;
    }

    resource function get assets() returns Asset[] {
        lock {
            return assetTable.toArray().clone();
        }
    }

    resource function get assets/[string assetTag]() returns Asset|http:NotFound {
        lock {
            if assetTable.hasKey(assetTag) {
                return assetTable.get(assetTag).clone();
            }
        }
        return http:NOT_FOUND;
    }

    resource function put assets/[string assetTag](@http:Payload Asset updated) returns Asset|http:NotFound {
        lock {
            if !assetTable.hasKey(assetTag) {
                return http:NOT_FOUND;
            }
            assetTable.put(updated.clone());
        }
        return updated;
    }

    resource function delete assets/[string assetTag]() returns http:Ok|http:NotFound {
        lock {
            if !assetTable.hasKey(assetTag) {
                return http:NOT_FOUND;
            }
            _ = assetTable.remove(assetTag);
        }
        return http:OK;
    }

    // ---------------- INSTITUTION / SITE FILTERING ----------------

    resource function get institutions/[string institution]/assets() returns Asset[] {
        lock {
            return from Asset a in assetTable
                where a.institution == institution
                select a.clone();
        }
    }

    resource function get institutions/[string institution]/sites/[string site]/assets() returns Asset[] {
        lock {
            return from Asset a in assetTable
                where a.institution == institution && a.site == site
                select a.clone();
        }
    }

    // Removes an institution by clearing out every asset tagged to it.
    resource function delete institutions/[string institution]() returns http:Ok {
        lock {
            table<Asset> key(assetTag) remaining = table key(assetTag) [];
            foreach Asset a in assetTable {
                if a.institution != institution {
                    remaining.add(a.clone());
                }
            }
            assetTable = remaining;
        }
        return http:OK;
    }

    // ---------------- WORK ORDERS & TASKS ----------------

    resource function post assets/[string assetTag]/workorders(@http:Payload WorkOrder wo) returns WorkOrder|http:NotFound {
        lock {
            if !assetTable.hasKey(assetTag) {
                return http:NOT_FOUND;
            }
            Asset a = assetTable.get(assetTag);
            a.workOrders.push(wo.clone());
            assetTable.put(a);
        }
        return wo;
    }

    resource function get assets/[string assetTag]/workorders() returns WorkOrder[]|http:NotFound {
        lock {
            if !assetTable.hasKey(assetTag) {
                return http:NOT_FOUND;
            }
            return assetTable.get(assetTag).workOrders.clone();
        }
    }

    resource function put assets/[string assetTag]/workorders/[string orderId](string status) returns WorkOrder|http:NotFound {
        lock {
            if !assetTable.hasKey(assetTag) {
                return http:NOT_FOUND;
            }
            Asset a = assetTable.get(assetTag);
            foreach WorkOrder wo in a.workOrders {
                if wo.orderId == orderId {
                    wo.status = status;
                    assetTable.put(a);
                    return wo.clone();
                }
            }
            return http:NOT_FOUND;
        }
    }

    resource function delete assets/[string assetTag]/workorders/[string orderId]() returns http:Ok|http:NotFound {
        lock {
            if !assetTable.hasKey(assetTag) {
                return http:NOT_FOUND;
            }
            Asset a = assetTable.get(assetTag);
            a.workOrders = a.workOrders.filter(wo => wo.orderId != orderId);
            assetTable.put(a);
        }
        return http:OK;
    }

    resource function post assets/[string assetTag]/workorders/[string orderId]/tasks(@http:Payload Task t) returns Task|http:NotFound {
        lock {
            if !assetTable.hasKey(assetTag) {
                return http:NOT_FOUND;
            }
            Asset a = assetTable.get(assetTag);
            foreach WorkOrder wo in a.workOrders {
                if wo.orderId == orderId {
                    wo.tasks.push(t.clone());
                    assetTable.put(a);
                    return t;
                }
            }
            return http:NOT_FOUND;
        }
    }

    resource function delete assets/[string assetTag]/workorders/[string orderId]/tasks/[string taskId]() returns http:Ok|http:NotFound {
        lock {
            if !assetTable.hasKey(assetTag) {
                return http:NOT_FOUND;
            }
            Asset a = assetTable.get(assetTag);
            foreach WorkOrder wo in a.workOrders {
                if wo.orderId == orderId {
                    wo.tasks = wo.tasks.filter(t => t.taskId != taskId);
                    assetTable.put(a);
                    return http:OK;
                }
            }
            return http:NOT_FOUND;
        }
    }
}


