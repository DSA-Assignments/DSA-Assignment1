// Shared data models for the Rental Accommodation System server.
// Field names match rental.proto so swapping these for the generated
// message records (after `bal build` on the proto) is a direct rename.
//
// Person 6 (host-side) writes to `propertyTable` via addProperty /
// updateProperty / removeProperty / createUsers.
// Person 7 (guest-side, this module) mostly reads propertyTable and owns
// `bookingCart`.

public type Property record {|
    string propertyId;
    string name;
    string location;
    string propertyType;
    decimal pricePerNight;
    string status; // AVAILABLE, BOOKED
    string hostId;
|};

public type BookingCartEntry record {|
    string propertyId;
    string guestId;
    string checkIn;  // YYYY-MM-DD
    string checkOut; // YYYY-MM-DD
|};

isolated table<Property> key(propertyId) propertyTable = table [];
isolated map<BookingCartEntry> bookingCart = {}; // keyed by guestId
