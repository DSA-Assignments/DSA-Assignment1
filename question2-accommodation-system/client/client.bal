import ballerina/io;
import rental; // generated from ../proto/rental.proto via `bal build`

// Task 8: gRPC client demonstrating every operation.
//
// The exact generated type/method names below (RentalServiceClient,
// UserProfileStreamingClient, etc.) follow Ballerina's standard gRPC codegen
// conventions, but confirm the actual names once `bal build` generates the
// client stub from rental.proto — rename here if they differ.

public function main() returns error? {
    rental:RentalServiceClient rentalClient = check new ("http://localhost:9090");

    // 1. add_property
    rental:Property newProperty = {
        propertyId: "",
        name: "Seaside Cottage",
        location: "Swakopmund",
        propertyType: "Cottage",
        pricePerNight: 120.0,
        status: "AVAILABLE",
        hostId: "host-01"
    };
    rental:PropertyId createdId = check rentalClient->addProperty(newProperty);
    io:println("Created property: ", createdId.propertyId);

    // 2. create_users (client-streaming)
    rental:UserProfileStreamingClient userStream = check rentalClient->createUsers();
    check userStream->sendUserProfile({userId: "host-01", name: "Host One", role: "HOST"});
    check userStream->sendUserProfile({userId: "guest-01", name: "Guest One", role: "GUEST"});
    check userStream->complete();
    rental:UserCreationSummary summary = check userStream->receiveUserCreationSummary();
    io:println("Users created: ", summary.usersCreated);

    // 3. update_property
    rental:Property updatedProperty = check rentalClient->updateProperty({
        propertyId: createdId.propertyId,
        pricePerNight: 150.0,
        status: "AVAILABLE"
    });
    io:println("Updated price per night: ", updatedProperty.pricePerNight);

    // 4. list_available_properties (server-streaming)
    stream<rental:Property, error?> listings = check rentalClient->listAvailableProperties({
        location: "Swakopmund",
        maxPrice: 500.0
    });
    check listings.forEach(function(rental:Property p) {
        io:println("Available: ", p.name, " - N$", p.pricePerNight, "/night");
    });

    // 5. search_property
    rental:SearchResult found = check rentalClient->searchProperty({propertyId: createdId.propertyId});
    io:println("Search status: ", found.status);

    // 6. book_property
    rental:BookingCartResult bookingResult = check rentalClient->bookProperty({
        propertyId: createdId.propertyId,
        guestId: "guest-01",
        checkIn: "2026-10-01",
        checkOut: "2026-10-05"
    });
    io:println("Booking cart: ", bookingResult.message);

    // 7. confirm_booking
    rental:BookingConfirmation confirmation = check rentalClient->confirmBooking({propertyId: createdId.propertyId});
    io:println("Confirmed: ", confirmation.confirmed, " | Total cost: N$", confirmation.totalCost);

    // 8. remove_property
    rental:PropertyList remaining = check rentalClient->removeProperty({propertyId: createdId.propertyId});
    io:println("Remaining properties for this host: ", remaining.properties.length());
}

