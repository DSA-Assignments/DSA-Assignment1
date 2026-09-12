import ballerina/uuid;

// Task 6: Host-side server logic.

// This module owns `propertyTable` (writes) and `userTable` (owns fully).
// guest_logic.bal (Task 7) only ever reads `propertyTable`.

public type UserProfile record {|
    string userId;
    string name;
    string role; // HOST or GUEST
|};

isolated map<UserProfile> userTable = {}; // keyed by userId

// ==================== add_property ====================

// Mirrors the proto Property message. propertyId may arrive blank from the
// client (as in client.bal's example) — the server assigns one in that case.
public type NewPropertyInput record {|
    string propertyId;
    string name;
    string location;
    string propertyType;
    decimal pricePerNight;
    string status;
    string hostId;
|};

public isolated function addProperty(NewPropertyInput input) returns string|error {
    if input.hostId.trim() == "" {
        return error("hostId is required.");
    }
    if input.pricePerNight <= 0d {
        return error("pricePerNight must be positive.");
    }

    string propertyId = input.propertyId.trim();
    if propertyId == "" {
        propertyId = uuid:createType1AsString();
    }

    string status = input.status.trim() == "" ? "AVAILABLE" : input.status;

    lock {
        if propertyTable.hasKey(propertyId) {
            return error("Property id already exists: " + propertyId);
        }
        Property newProperty = {
            propertyId,
            name: input.name,
            location: input.location,
            propertyType: input.propertyType,
            pricePerNight: input.pricePerNight,
            status,
            hostId: input.hostId
        };
        propertyTable.add(newProperty.clone());
    }
    return propertyId;
}

// ==================== update_property ====================
// Matches proto UpdatePropertyRequest: only price and status are mutable
// through this RPC.

public type UpdatePropertyInput record {|
    string propertyId;
    decimal pricePerNight;
    string status;
|};

public isolated function updateProperty(UpdatePropertyInput input) returns Property|error {
    lock {
        if !propertyTable.hasKey(input.propertyId) {
            return error("Property not found: " + input.propertyId);
        }
        Property p = propertyTable.get(input.propertyId);

        if input.pricePerNight > 0d {
            p.pricePerNight = input.pricePerNight;
        }
        if input.status.trim() != "" {
            p.status = input.status;
        }

        propertyTable.put(p);
        return p.clone();
    }
}

// ==================== remove_property ====================
// The proto's PropertyList response and client.bal's "Remaining properties
// for this host" comment imply the response lists the *removed property's
// host's* other listings, not the whole table.

public isolated function removeProperty(string propertyId) returns Property[]|error {
    lock {
        if !propertyTable.hasKey(propertyId) {
            return error("Property not found: " + propertyId);
        }
        Property removed = propertyTable.get(propertyId);
        _ = propertyTable.remove(propertyId);

        return from Property p in propertyTable
            where p.hostId == removed.hostId
            select p.clone();
    }
}

// ==================== create_users (client-streaming) ====================
// The client streams UserProfile messages one at a time and then closes the
// stream, expecting a single UserCreationSummary back. registerUser() below
// is meant to be called once per message as it arrives off the wire;
// createUsers() is a batch convenience wrapper (handy for unit tests, and
// usable directly if the generated skeleton hands back the whole message
// list rather than calling back per-message — see wiring notes below).

public isolated function registerUser(UserProfile profile) returns error? {
    if profile.userId.trim() == "" {
        return error("userId is required.");
    }
    if profile.role != "HOST" && profile.role != "GUEST" {
        return error("Invalid role for user '" + profile.userId + "': " + profile.role);
    }
    lock {
        userTable[profile.userId] = profile.clone();
    }
}

public type UserCreationOutcome record {|
    int usersCreated;
|};

public isolated function createUsers(UserProfile[] profiles) returns UserCreationOutcome {
    int created = 0;
    foreach UserProfile profile in profiles {
        error? result = registerUser(profile);
        if result is () {
            created += 1;
        }
    }
    return { usersCreated: created };
}

public isolated function totalUsers() returns int {
    lock {
        return userTable.length();
    }
}
