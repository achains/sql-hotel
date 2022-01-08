/*
 * Author: Arthur Chains, https://github.com/achains
 * Date of creation: 01.06
 */


-- 1. Show every reservation that have description (Also search in Archive)
SELECT reservation.reservation_id, reservation.description, 'current' AS "relevance"
FROM reservation WHERE reservation.description IS NOT NULL
UNION
SELECT archive_reservation.reservation_id, archive_reservation.description, 'archive'
FROM archive_reservation WHERE archive_reservation.description IS NOT NULL;

-- 2. Order rooms by occupied number
SELECT room_type.name, room_type.is_vip, SUM(v_reserved_room.amount) AS reserved_number
FROM room_type JOIN v_reserved_room ON room_type.room_type_id = v_reserved_room.room_type_id
GROUP BY room_type.room_type_id ORDER BY reserved_number DESC;

-- 3. Staff and their basic service
SELECT s.staff_id, s2.name AS "service_name"
FROM staff_service JOIN staff s ON staff_service.staff_id = s.staff_id
                   JOIN service s2 ON staff_service.service_id = s2.service_id
WHERE staff_service.is_basic_service;

-- 4. Services ordered by booking frequency
SELECT service.name, COUNT(*) AS reserved_number
FROM reservation_service JOIN service ON reservation_service.service_id = service.service_id
GROUP BY service.service_id ORDER BY reserved_number;

-- 5. Room types that are in the current reservations
SELECT DISTINCT room_type.name
FROM v_reserved_room JOIN room_type ON v_reserved_room.room_type_id = room_type.room_type_id;

-- 6. Modify services table, set cost of positions with Null to 50 [OR 70 if there is staff with basic skill]
UPDATE service
    SET price =
(
    CASE WHEN price IS NULL THEN
        CASE WHEN (SELECT service_id IN (SELECT service_id FROM staff_service WHERE is_basic_service))
        THEN
        70
        ELSE
        50
        END
    ELSE
        price
    END
);

-- 7. Arrival dates
SELECT client.last_name, client.first_name, reservation.date_start
FROM reservation JOIN client ON reservation.client_id = client.client_id
ORDER BY date_start;

-- 8. Sort rooms by capacity
SELECT room_type.name, room_type.price, room_type.capacity
FROM room_type ORDER BY capacity DESC;

-- 9. NOT prepaid reservations, in which client has Trusted status
SELECT reservation.reservation_id, client.client_id, client.last_name, client.first_name
FROM reservation JOIN client ON reservation.client_id = client.client_id
WHERE NOT reservation.is_paid AND client.is_trusted;

-- 10. Total cost of reservation for people, who canceled free services
SELECT client.last_name, client.first_name, (SELECT getTotalCost(reservation.reservation_id))
FROM client JOIN reservation ON client.client_id = reservation.client_id
WHERE NOT reservation.free_included;

-- 11. Name of people who paid for services more than 100 units
SELECT client.last_name, client.first_name, SUM(s.price) AS total_price
FROM client JOIN reservation ON client.client_id = reservation.client_id
            JOIN reservation_room_type rrt ON reservation.reservation_id = rrt.reservation_id
            JOIN reservation_service rs on reservation.reservation_id = rs.reservation_id
            JOIN service s on rs.service_id = s.service_id
GROUP BY client.client_id HAVING(SUM(s.price) > 100);

-- 12. All client and their reservations
SELECT client.client_id, client.last_name, client.first_name, reservation_id
FROM client LEFT OUTER JOIN reservation ON client.client_id = reservation.client_id;
