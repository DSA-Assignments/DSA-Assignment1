public type Host record {|
    string id;
    string name;
    string email;
    string phone;
    string[] accommodationIds = [];
|};

public type Accommodation record {|
    string id;
    string title;
    string location;
    int capacity;
    decimal pricePerNight;
    boolean isAvailable = true;
    string hostId;
|};

public type Booking record {|
    string id;
    string accommodationId;
    string guestName;
    string guestEmail;
    string checkIn;
    string checkOut;
|};

public class HostLogic {
    private map<Host> hosts = {};
    private map<Accommodation> accommodations = {};
    private map<Booking[]> bookingsByAccommodation = {};

    public function registerHost(Host host) returns Host|error {
        if host.id == "" || host.name == "" {
            return error("Host id and name are required.");
        }

        if self.hosts.hasKey(host.id) {
            return error("Host already exists: " + host.id);
        }

        self.hosts[host.id] = host;
        return host;
    }

    public function getHost(string hostId) returns Host? {
        return self.hosts[hostId];
    }

    public function addAccommodation(string hostId, Accommodation accommodation) returns Accommodation|error {
        if !self.hosts.hasKey(hostId) {
            return error("Unknown host: " + hostId);
        }

        if accommodation.id == "" {
            return error("Accommodation id is required.");
        }

        if self.accommodations.hasKey(accommodation.id) {
            return error("Accommodation already exists: " + accommodation.id);
        }

        accommodation.hostId = hostId;
        self.accommodations[accommodation.id] = accommodation;

        Host host = self.hosts.get(hostId);
        host.accommodationIds.push(accommodation.id);
        self.hosts[hostId] = host;
        self.bookingsByAccommodation[accommodation.id] = [];

        return accommodation;
    }

    public function listAccommodations(string hostId) returns Accommodation[]|error {
        if !self.hosts.hasKey(hostId) {
            return error("Unknown host: " + hostId);
        }

        Host host = self.hosts.get(hostId);
        Accommodation[] result = [];

        foreach string accommodationId in host.accommodationIds {
            Accommodation? accommodation = self.accommodations[accommodationId];
            if accommodation is Accommodation {
                result.push(accommodation);
            }
        }

        return result;
    }

    public function updateAvailability(string accommodationId, boolean isAvailable) returns Accommodation|error {
        Accommodation? accommodation = self.accommodations[accommodationId];
        if accommodation is () {
            return error("Accommodation not found: " + accommodationId);
        }

        accommodation.isAvailable = isAvailable;
        self.accommodations[accommodationId] = accommodation;
        return accommodation;
    }

    public function createBooking(string accommodationId, Booking booking) returns Booking|error {
        Accommodation? accommodation = self.accommodations[accommodationId];
        if accommodation is () {
            return error("Accommodation not found: " + accommodationId);
        }

        if !accommodation.isAvailable {
            return error("Accommodation is not available for booking.");
        }

        if booking.id == "" {
            return error("Booking id is required.");
        }

        Booking[] existingBookings = self.bookingsByAccommodation.hasKey(accommodationId)
            ? self.bookingsByAccommodation.get(accommodationId)
            : [];

        foreach Booking existingBooking in existingBookings {
            if existingBooking.id == booking.id {
                return error("Booking already exists: " + booking.id);
            }
        }

        existingBookings.push(booking);
        self.bookingsByAccommodation[accommodationId] = existingBookings;

        accommodation.isAvailable = false;
        self.accommodations[accommodationId] = accommodation;

        return booking;
    }

    public function getBookings(string accommodationId) returns Booking[]|error {
        if !self.accommodations.hasKey(accommodationId) {
            return error("Accommodation not found: " + accommodationId);
        }

        return self.bookingsByAccommodation.hasKey(accommodationId)
            ? self.bookingsByAccommodation.get(accommodationId)
            : [];
    }
}

public function createHostLogic() returns HostLogic {
    return new HostLogic();
}
