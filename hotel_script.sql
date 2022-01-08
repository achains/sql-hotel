/*
 * Author: Arthur Chains, https://github.com/achains
 * Date of creation: 01.03
 */

/***********************************************************************************************************************
                                                    TABLES
***********************************************************************************************************************/

CREATE TABLE client(
    client_id INTEGER NOT NULL,
    last_name VARCHAR(32) NOT NULL,
    first_name VARCHAR(32) NOT NULL,
    phone VARCHAR(16),
    is_trusted BOOL,
    passport_number VARCHAR(16) NOT NULL UNIQUE,
CONSTRAINT client_pk PRIMARY KEY (client_id)
);

CREATE TABLE staff(
    staff_id INTEGER NOT NULL,
    specialization VARCHAR(64),
    description VARCHAR(128),
CONSTRAINT staff_pk PRIMARY KEY (staff_id)
);

CREATE TABLE service(
    service_id INTEGER NOT NULL,
    name VARCHAR(64),
    price FLOAT,
CONSTRAINT service_pk PRIMARY KEY (service_id)
);

CREATE TABLE staff_service(
    staff_id INTEGER NOT NULL,
    service_id INTEGER NOT NULL,
    is_basic_service BOOL
);

CREATE TABLE room_type(
    room_type_id INTEGER NOT NULL,
    name VARCHAR(32),
    price FLOAT,
    capacity INTEGER,
    is_vip BOOL,
    number_of_rooms INTEGER,
    description VARCHAR(128),
CONSTRAINT room_type_pk PRIMARY KEY (room_type_id)
);

CREATE TABLE reservation(
    reservation_id INTEGER NOT NULL,
    client_id INTEGER NOT NULL,
    payment_type VARCHAR(32),
    is_paid BOOL,
    free_included BOOL,
    date_start DATE NOT NULL,
    date_end DATE,
    description VARCHAR(128),
CONSTRAINT reservation_pk PRIMARY KEY (reservation_id)
);

CREATE TABLE archive_reservation(
    reservation_id  INTEGER NOT NULL,
    client_id INTEGER NOT NULL,
    is_paid BOOL,
    date_start DATE NOT NULL,
    date_end DATE,
    description VARCHAR(128)
);

CREATE TABLE reservation_room_type(
    reservation_id INTEGER NOT NULL,
    room_type_id INTEGER NOT NULL,
    amount INTEGER
);

CREATE TABLE reservation_service(
    reservation_id INTEGER NOT NULL,
    service_id INTEGER NOT NULL
);


/***********************************************************************************************************************
                                                    FOREIGN KEYS
***********************************************************************************************************************/

ALTER TABLE reservation ADD CONSTRAINT fk_reserv_client
    FOREIGN KEY (client_id)
    REFERENCES client(client_id)
;

ALTER TABLE reservation_room_type ADD CONSTRAINT fk_r_rt_reserv
    FOREIGN KEY (reservation_id)
    REFERENCES reservation(reservation_id) ON DELETE CASCADE
;

ALTER TABLE reservation_room_type ADD CONSTRAINT fk_r_rt_rt
    FOREIGN KEY (room_type_id)
    REFERENCES room_type(room_type_id)
;

ALTER TABLE staff_service ADD CONSTRAINT fk_st_s_staff
    FOREIGN KEY (staff_id)
    REFERENCES staff(staff_id)
;

ALTER TABLE staff_service ADD CONSTRAINT fk_st_s_service
    FOREIGN KEY (service_id)
    REFERENCES service(service_id)
;

ALTER TABLE reservation_service ADD CONSTRAINT r_s_reserv
    FOREIGN KEY (reservation_id)
    REFERENCES reservation(reservation_id) ON DELETE CASCADE
;

ALTER TABLE reservation_service ADD CONSTRAINT r_s_service
    FOREIGN KEY (service_id)
    REFERENCES service(service_id)
;

/***********************************************************************************************************************
                                                     INDICES
***********************************************************************************************************************/
CREATE INDEX idx_date ON reservation(date_start, date_end);
CREATE INDEX idx_room_reserv_amount ON reservation_room_type(amount);
CREATE INDEX idx_reserv_description ON reservation(description);

/***********************************************************************************************************************
                                                      VIEWS
***********************************************************************************************************************/
-- Description: Show room types and the date of their reservation
CREATE VIEW v_reserved_room
    (room_type_id, amount, date_start, date_end)
AS
    SELECT room_type_id, amount, date_start, date_end
    FROM reservation_room_type JOIN reservation ON
         reservation_room_type.reservation_id = reservation.reservation_id;

-- Description: Show price list of reservation (room cost, service cost)
CREATE VIEW v_reservation_cost
    (reservation_id, total_room_cost, total_service_cost)
AS
    SELECT reservation.reservation_id, SUM(room_type.price) as total_room_cost, SUM(service.price) as total_service_cost
    FROM reservation JOIN reservation_room_type rrt ON reservation.reservation_id = rrt.reservation_id
                     JOIN room_type ON rrt.room_type_id = room_type.room_type_id
                     JOIN reservation_service rs ON reservation.reservation_id = rs.reservation_id
                     JOIN service ON rs.service_id = service.service_id
    GROUP BY reservation.reservation_id ORDER BY reservation_id;

-- Description: Show list of all zero cost services
CREATE VIEW v_free_service
    (service_id, name)
AS
    SELECT service.service_id, service.name
    FROM service WHERE service.price = 0.0;
/***********************************************************************************************************************
                                                    FUNCTIONS
***********************************************************************************************************************/
-- Description: Get number of available rooms of given category for a certain date
-- Example: SELECT getAvailableRooms(2, '2022-01-12', '2022-01-16');
CREATE OR REPLACE FUNCTION getAvailableRooms(
    var_room_type_id INT,
    var_date_from DATE,
    var_date_to DATE
)
RETURNS INT
AS
$body$
DECLARE
    reserved_number INT;
BEGIN
    SELECT SUM(amount) INTO reserved_number FROM v_reserved_room
    WHERE room_type_id = var_room_type_id AND
    (var_date_from >= v_reserved_room.date_start AND var_date_from <= v_reserved_room.date_end OR
     var_date_to >= v_reserved_room.date_start AND var_date_to <= v_reserved_room.date_end);
    RETURN (SELECT number_of_rooms - reserved_number FROM room_type WHERE room_type_id = var_room_type_id);
END;
$body$
language plpgsql;

-- Description: Add room to reservation
-- Example: CALL addRoom(2, 2, 1);
CREATE OR REPLACE PROCEDURE addRoom(
    var_reservation_id INT,
    var_room_type_id INT,
    var_number_of_rooms INT
)
AS
$body$
BEGIN
    IF (SELECT var_reservation_id NOT IN (SELECT reservation_id FROM reservation)) THEN
        RAISE 'Can not add room to reservation: Reservation with such ID does not exists';
    END IF;

    INSERT INTO reservation_room_type(reservation_id, room_type_id, amount)
    VALUES (var_reservation_id, var_room_type_id, var_number_of_rooms);

END;
$body$
language plpgsql;

-- Description: Get reservation total cost
-- Example: SELECT getTotalCost(2);
CREATE OR REPLACE FUNCTION getTotalCost(
    var_reservation_id INT
)
RETURNS FLOAT
AS
$body$
DECLARE
    total_cost FLOAT;
BEGIN
    SELECT total_room_cost + total_service_cost INTO total_cost FROM v_reservation_cost
    WHERE v_reservation_cost.reservation_id = var_reservation_id;

    RETURN total_cost;
END;
$body$
language plpgsql;

/***********************************************************************************************************************
                                                    TRIGGERS
***********************************************************************************************************************/
-- Description: Add Free Services to reservation IF free_included is set
-- Example:
-- UPDATE reservation SET free_included = true WHERE reservation_id = 7;
-- SELECT service_id FROM reservation_service WHERE reservation_id = 7;
CREATE OR REPLACE FUNCTION addFreeService()
RETURNS TRIGGER
AS
$body$
BEGIN
    IF NEW.free_included <> OLD.free_included AND NEW.free_included OR
       OLD.free_included IS NULL AND NEW.free_included
    THEN
        INSERT INTO reservation_service(reservation_id, service_id)
        SELECT NEW.reservation_id AS reservation_id, service_id FROM v_free_service;
    END IF;
    RETURN NULL;
END;
$body$
language plpgsql;

CREATE TRIGGER trAddFree
    AFTER INSERT OR UPDATE
    ON reservation
    FOR EACH ROW
EXECUTE PROCEDURE addFreeService();

-- Description: Instead of Deleting reservation, move it to Archive
-- Example:
-- DELETE FROM reservation WHERE reservation_id = 3;
-- SELECT * FROM archive_reservation WHERE reservation_id = 3;
CREATE OR REPLACE FUNCTION moveToArchive()
RETURNS TRIGGER
AS
$body$
BEGIN
    INSERT INTO archive_reservation(reservation_id, client_id, is_paid, date_start, date_end, description)
    VALUES (OLD.reservation_id, OLD.client_id, OLD.is_paid, OLD.date_start, OLD.date_end, OLD.description);

    RETURN OLD;
END;
$body$
language plpgsql;

CREATE TRIGGER trDelReservation
    BEFORE DELETE
    ON reservation
    FOR EACH ROW
EXECUTE PROCEDURE moveToArchive();

-- Description: Check whether amount of reserving rooms is NOT GREATER than number of free rooms
-- Example:
-- INSERT INTO reservation_room_type(reservation_id, room_type_id, amount)
-- VALUES (1, 3, 1000);
CREATE OR REPLACE FUNCTION checkRoom()
RETURNS TRIGGER
AS
$body$
DECLARE
    var_date_from DATE;
    var_date_to DATE;
    var_number_of_rooms INT;
BEGIN
    SELECT INTO var_date_from, var_date_to
           date_start, date_end
    FROM reservation WHERE reservation_id = NEW.reservation_id;

    SELECT number_of_rooms INTO var_number_of_rooms
    FROM room_type WHERE room_type.room_type_id = NEW.room_type_id;

    IF getAvailableRooms(NEW.room_type_id, var_date_from, var_date_to) < NEW.amount AND
       (NEW.amount <> OLD.amount OR OLD.amount IS NULL)
    THEN
       RAISE 'Reserved Room Number is GREATER than available room number';
    END IF;
    RETURN NEW;
END;
$body$
language plpgsql;

CREATE TRIGGER trCheckRoom
    BEFORE UPDATE OR INSERT
    ON reservation_room_type
    FOR EACH ROW
EXECUTE PROCEDURE checkRoom();

/***********************************************************************************************************************
                                            FILL TABLES WITH TEST DATA
***********************************************************************************************************************/
INSERT INTO client(client_id, last_name, first_name, phone, is_trusted, passport_number)
VALUES
    (1, 'Ivanov', 'Ivan', '+79000000000', true, '11223300'),
    (2, 'Hurah', 'Mansur', '79000000001', true, '11123144'),
    (3, 'Enotov', 'Pavel', '+79000000002', false, '44114151'),
    (4, 'Kotova', 'Valeriya', '+79000000003', false, '513513515'),
    (5, 'Toporov', 'Timofey', '+79100000004', NULL, '125111242'),
    (6, 'Sokolov', 'Stepan', '+79030000000', true, '1241241222'),
    (7, 'Eryomin', 'Vladimir', '79000090000', false, '1221244444'),
    (8, 'Topoleva', 'Pianina', '+79000000017', NULL, '12324124154'),
    (9, 'Ryabova', 'Alexandra', '+79000000090', NULL, '8753213118'),
    (10, 'Goncharov', 'Vsevolod', '79000034000', true, '68584256644'),
    (11, 'Goncharov', 'Stepan', '+79033000000', false, '9859135151'),
    (12, 'Kleshin', 'Timur', '79000093000', NULL, '97159719510'),
    (13, 'Kotova', 'Tatyana', '8918063913', NULL, '315158481'),
    (14, 'Bert', 'Albert', '+031391844', false, '3144611351')
;

INSERT INTO staff(staff_id, specialization, description)
VALUES
    (1, 'Cleaning', NULL),
    (2, 'Cleaning', 'Internship'),
    (3, 'Driver', NULL),
    (4, 'Driver', 'Soon retire'),
    (5, 'Driver', NULL),
    (6, 'Cleaning', NULL),
    (7, 'Barista', NULL),
    (8, 'Chef', 'Premium food'),
    (9, 'Chef', NULL),
    (10, 'Babysitter', NULL)
;

INSERT INTO service(service_id, name, price)
VALUES
    (1, 'Cook food', NULL),
    (2, 'Clean room', 0.),
    (3, 'Park car', 0.),
    (4, 'Clean clothes', 45.),
    (5, 'Make cocktail', NULL),
    (6, 'Sit with baby', 85.),
    (7, 'Bottle of water', 0.)
;

INSERT INTO staff_service(staff_id, service_id, is_basic_service)
VALUES
    (1, 2, true),
    (1, 7, true),
    (2, 4, NULL),
    (7, 5, true),
    (8, 5, false),
    (9, 5, NULL),
    (1, 6, false),
    (10, 6, true)
;

INSERT INTO room_type(room_type_id, name, price, capacity, is_vip, number_of_rooms, description)
VALUES
    (1, 'Default', 35.50, 2, false, 30, 'One queen-size bed, one own bathroom'),
    (2, 'Default Big', 47.80, 5, NULL, 25, 'One king-size bed, two sofas, one bathroom, one additional toilet'),
    (3, 'Suite', 85, 2, false, 14, 'Luxury room with one king-size bed and big bathroom. Beautiful view from window'),
    (4, 'Suite VIP', 120, 4, true, 6, 'Luxury room, Super king-size bed, bathroom with jacuzzi'),
    (5, 'President', 180, 2, true, NULL, '!!! Under Repair !!! Temporarily Unavailable !!!')
;

INSERT INTO reservation(reservation_id, client_id, payment_type, is_paid, free_included, date_start, date_end, description)
VALUES
    (1, 3, NULL, NULL, true, '2022-01-02', '2022-01-09', 'Problem with payment, but it is trusted client'),
    (2, 4, 'Online. Card', true, true, '2022-01-15', '2022-01-16', NULL),
    (3, 4, 'Online. Card', true, true, '2022-02-20', '2022-03-05', NULL),
    (4, 1, 'On the spot', false, false, '2022-01-13', NULL, NULL),
    (5, 2, 'On the spot', false, true, '2022-01-01', '2022-01-16', 'With little baby'),
    (6, 5, 'Online. Card', true, false, '2022-02-02', NULL, NULL),
    (7, 14, 'Online. Card', true, false, '2022-02-03', '2022-02-23', 'Speaking only french'),
    (8, 11, 'On the spot', false, false, '2022-05-15', '2022-05-18', 'Birthday during reservation'),
    (9, 2, 'Online. Card', true, true, '2022-03-12', NULL, NULL)
;

INSERT INTO archive_reservation(reservation_id, client_id, is_paid, date_start, date_end, description)
VALUES
    (90, 3, true, '2019-01-09', '2019-02-10', NULL),
    (91, 1, true, '2018-01-01', '2018-01-15', 'I want to sleep badly'),
    (92, 1, false, '2017-01-01', '2015-01-04', NULL),
    (93, 4, true, '2020-01-01', '2020-01-02', NULL),
    (94, 5, true, '2020-01-01', NULL, NULL);

INSERT INTO reservation_service(reservation_id, service_id)
VALUES
    (1, 2), (2, 2), (3, 2), (4, 5), (5, 2), (6, 1), (7, 1), (8, 1), (9, 2), (9, 5),
    (1, 3), (2, 3), (3, 3),         (5, 3), (6, 2), (7, 5),         (9, 3), (9, 4),
    (1, 7), (2, 7), (3, 7),         (5, 7),         (7, 7),         (9, 7), (9, 6)
;

INSERT INTO reservation_room_type(reservation_id, room_type_id, amount)
VALUES
    (1, 1, NULL), (2, 2, 1), (2, 1, 1),
    (3, 4, 1), (4, 3, 1), (5, 2, 1),
    (5, 3, 1), (6, 1, 1), (7, 4, 1),
    (8, 1, 5), (8, 2, 3), (8, 4, 1),
    (9, 3, 1)
;

/***********************************************************************************************************************
                                                   DROP VIEWS
***********************************************************************************************************************/
DROP VIEW v_free_service;
DROP VIEW v_reserved_room;
DROP VIEW v_reservation_cost;

/***********************************************************************************************************************
                                                   DROP TABLES
***********************************************************************************************************************/
DROP TABLE reservation_room_type;
DROP TABLE room_type;
DROP TABLE staff_service;
DROP TABLE staff;
DROP TABLE reservation_service;
DROP TABLE service;
DROP TABLE reservation;
DROP TABLE client;
DROP TABLE archive_reservation;
