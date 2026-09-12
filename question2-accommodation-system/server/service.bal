// service.bal
// Task: gRPC service wiring.
//
// Connects the generated RentalService skeleton to the plain functions in
// host_logic.bal (Person 6) and guest_logic.bal (Person 7). Neither of those
// modules touches gRPC types directly, so this file is the single place where
// generated message records are converted to and from our internal records.
//
// ---------------------------------------------------------------------------
// BEFORE THIS COMPILES
// ---------------------------------------------------------------------------
// 1. Generate the stub:
//        bal grpc --input ../proto/rental.proto --output .
//    That produces rental_pb.bal containing the message records, the
//    descriptor constants and the streaming caller types.
//
// 2. Open rental_pb.bal and check the generated names against the ones used
//    below. Message record names come straight from the proto, so if the
//    proto calls it `PropertyResponse` and this file says `PropertyReply`,
//    rename here. The names assumed below follow the RPC names listed in
//    WIRING_NOTES.md.
//
// 3. The confirmBooking proto change described in WIRING_NOTES.md must be
//    applied first — see the note on that method below.
// ---------------------------------------------------------------------------

import ballerina/grpc;
import ballerina/log;

@grpc:ServiceDescriptor {
    descriptor: ROOT_DESCRIPTOR_RENTAL,
    descMap: getDescriptorMapRental()
}
service "RentalService" on new grpc:Listener(9090) {

    // =======================================================================
    // HOST-SIDE OPERATIONS  ->  host_logic.bal
    // =======================================================================

    // add_property (Simple RPC)
    // Returns the assigned propertyId, which the server generates when the
    // client sends a blank one.
    remote function addProperty(AddPropertyRequest request)
            returns AddPropertyResponse|error {

        NewPropertyInput input = {
            propertyId: request.propertyId,
            name: request.name,
            location: request.location,
            propertyType: request.propertyType,
            pricePerNight: request.pricePerNight,
            status: request.status,
            hostId: request.hostId
        };

        string|error result = addProperty(input);

        if result is error {
            log:printError("addProperty rejected", 'error = result);
            return {
                success: false,
                propertyId: "",
                message: result.message()
            };
        }

        log:printInfo("Property registered", propertyId = result);
        return {
            success: true,
            propertyId: result,
            message: "Property registered successfully."
        };
    }

    // update_property (Simple RPC)
    // Only price and status are mutable through this RPC, matching
    // UpdatePropertyInput in host_logic.bal.
    remote function updateProperty(UpdatePropertyRequest request)
            returns UpdatePropertyResponse|error {

        UpdatePropertyInput input = {
            propertyId: request.propertyId,
            pricePerNight: request.pricePerNight,
            status: request.status
        };

        Property|error result = updateProperty(input);

        if result is error {
            return {
                success: false,
                message: result.message()
            };
        }

        return {
            success: true,
            message: "Property updated successfully.",
            property: toProtoProperty(result)
        };
    }

    // remove_property (Simple RPC)
    // Responds with the removed property's host's remaining listings, as
    // host_logic.bal's removeProperty already scopes the result that way.
    remote function removeProperty(RemovePropertyRequest request)
            returns PropertyList|error {

        Property[]|error remaining = removeProperty(request.propertyId);

        if remaining is error {
            log:printError("removeProperty failed", 'error = remaining);
            // No properties to return; the error message travels in the
            // gRPC status rather than the payload.
            return remaining;
        }

        ProtoProperty[] converted = [];
        foreach Property p in remaining {
            converted.push(toProtoProperty(p));
        }

        log:printInfo("Property removed", remaining = converted.length());
        return {properties: converted};
    }

    // create_users (Client-side streaming RPC)
    // The client streams UserProfile messages then half-closes; we reply once
    // with a single summary. registerUser() is called per message as it
    // arrives, which is what host_logic.bal documents as the intended use.
    remote function createUsers(stream<UserProfileMessage, grpc:Error?> clientStream)
            returns UserCreationSummary|error {

        int created = 0;
        int rejected = 0;
        string[] errors = [];

        check from UserProfileMessage msg in clientStream
            do {
                UserProfile profile = {
                    userId: msg.userId,
                    name: msg.name,
                    role: msg.role
                };

                error? result = registerUser(profile);
                if result is () {
                    created += 1;
                } else {
                    rejected += 1;
                    errors.push(result.message());
                }
            };

        log:printInfo("User batch processed",
                created = created, rejected = rejected);

        return {
            usersCreated: created,
            usersRejected: rejected,
            errors: errors,
            message: string `Registered ${created} user(s); rejected ${rejected}.`
        };
    }

    // =======================================================================
    // GUEST-SIDE OPERATIONS  ->  guest_logic.bal
    // =======================================================================

    // list_available_properties (Server-side streaming RPC)
    // guest_logic returns the whole matching array; we stream it back one
    // property at a time, which is what the proto contract promises.
    remote function listAvailableProperties(ListAvailableRequest request,
            ProtoPropertyCaller caller) returns error? {

        // An empty string or a zero price means "no filter" — guest_logic
        // already treats () and "" that way.
        string? location = request.location.trim() == "" ? () : request.location;
        decimal? maxPrice = request.maxPrice <= 0d ? () : request.maxPrice;

        Property[] matches = listAvailableProperties(location, maxPrice);

        foreach Property p in matches {
            check caller->sendProtoProperty(toProtoProperty(p));
        }

        log:printInfo("Streamed available properties", count = matches.length());
        check caller->complete();
        return;
    }

    // search_property (Simple RPC)
    // Returns "Not Available" when the property is absent, per the brief.
    remote function searchProperty(SearchPropertyRequest request)
            returns SearchPropertyResponse|error {

        SearchOutcome outcome = searchProperty(request.propertyId);

        if !outcome.available {
            return {
                found: false,
                status: outcome.status,
                message: "Not Available"
            };
        }

        Property? p = outcome.property;
        if p is () {
            // Defensive: available true with no property should not happen.
            return {
                found: false,
                status: "NOT_AVAILABLE",
                message: "Not Available"
            };
        }

        return {
            found: true,
            status: outcome.status,
            message: "Property found.",
            property: toProtoProperty(p)
        };
    }

    // book_property (Simple RPC)
    // Validates the dates and places the request in the guest's cart.
    remote function bookProperty(BookPropertyRequest request)
            returns BookPropertyResponse|error {

        BookingOutcome outcome = bookProperty(
                request.propertyId,
                request.guestId,
                request.checkIn,
                request.checkOut);

        return {
            accepted: outcome.accepted,
            message: outcome.message
        };
    }

    // confirm_booking (Simple RPC)
    //
    // -------------------------------------------------------------------
    // PROTO CHANGE REQUIRED — see WIRING_NOTES.md
    // -------------------------------------------------------------------
    // guest_logic.bal's confirmBooking takes a guestId, because bookingCart
    // in types.bal is keyed by guestId:
    //
    //     isolated map<BookingCartEntry> bookingCart = {}; // keyed by guestId
    //
    // The proto previously sent propertyId, which cannot be used to look up
    // a cart entry. ConfirmBookingRequest must therefore carry guestId:
    //
    //     message ConfirmBookingRequest {
    //         string guestId = 1;
    //     }
    //
    // Resolved in favour of guestId rather than re-keying the cart, because
    // "confirm the calling guest's cart" is the behaviour the brief
    // describes ("clear the Guest's temporary request") and re-keying by
    // propertyId would prevent one guest holding two pending requests.
    // -------------------------------------------------------------------
    remote function confirmBooking(ConfirmBookingRequest request)
            returns ConfirmBookingResponse|error {

        ConfirmationOutcome outcome = confirmBooking(request.guestId);

        if outcome.confirmed {
            log:printInfo("Booking confirmed",
                    guestId = request.guestId, total = outcome.totalCost);
        }

        return {
            confirmed: outcome.confirmed,
            totalCost: outcome.totalCost,
            message: outcome.message
        };
    }
}

// ===========================================================================
// Conversion helpers
// ===========================================================================

// Converts an internal Property into the generated proto message.
// Kept in one place so a proto field rename only needs fixing here.
//
// NOTE: `ProtoProperty` is a placeholder for whatever the generated record
// is called in rental_pb.bal — most likely just `Property`. If it is
// `Property`, the generated name will collide with our internal Property
// record in types.bal. Two ways to resolve that:
//   (a) import the generated module with a prefix, or
//   (b) rename the proto message to PropertyMessage and regenerate.
// Option (b) is simpler and is what this file assumes.
isolated function toProtoProperty(Property p) returns ProtoProperty {
    return {
        propertyId: p.propertyId,
        name: p.name,
        location: p.location,
        propertyType: p.propertyType,
        pricePerNight: p.pricePerNight,
        status: p.status,
        hostId: p.hostId
    };
}
