-- PROJECTHUB: ONE-CLICK DEMO DATABASE SETUP
-- MySQL 8.0+. This script DROPS and recreates the projecthub database.
-- All sample customer and supplier identities are fictional.
-- Run the entire file once in MySQL Workbench using Execute All.

DROP DATABASE IF EXISTS projecthub;
CREATE DATABASE projecthub CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE projecthub;

CREATE TABLE customers (
 customer_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 full_name VARCHAR(120) NOT NULL,
 phone VARCHAR(20), email VARCHAR(150), notes TEXT,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE KEY uq_customer_email (email)
) ENGINE=InnoDB;

CREATE TABLE projects (
 project_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 project_name VARCHAR(150) NOT NULL UNIQUE,
 description TEXT,
 default_selling_price DECIMAL(12,2) NOT NULL DEFAULT 0,
 active BOOLEAN NOT NULL DEFAULT TRUE,
 CHECK (default_selling_price >= 0)
) ENGINE=InnoDB;

CREATE TABLE orders (
 order_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 customer_id BIGINT UNSIGNED NOT NULL,
 order_date DATE NOT NULL,
 due_date DATE,
 status ENUM('PENDING','IN_PROGRESS','READY','DELIVERED','CANCELLED') NOT NULL DEFAULT 'PENDING',
 notes TEXT,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CONSTRAINT fk_order_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
 CHECK (due_date IS NULL OR due_date >= order_date)
) ENGINE=InnoDB;

CREATE TABLE order_items (
 order_item_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 order_id BIGINT UNSIGNED NOT NULL,
 project_id BIGINT UNSIGNED NOT NULL,
 quantity INT UNSIGNED NOT NULL,
 unit_price DECIMAL(12,2) NOT NULL,
 CONSTRAINT fk_item_order FOREIGN KEY (order_id) REFERENCES orders(order_id),
 CONSTRAINT fk_item_project FOREIGN KEY (project_id) REFERENCES projects(project_id),
 CHECK (quantity > 0), CHECK (unit_price >= 0)
) ENGINE=InnoDB;

CREATE TABLE payments (
 payment_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 order_id BIGINT UNSIGNED NOT NULL,
 paid_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 amount DECIMAL(12,2) NOT NULL,
 method ENUM('CASH','UPI','BANK_TRANSFER','OTHER') NOT NULL,
 reference_no VARCHAR(100),
 CONSTRAINT fk_payment_order FOREIGN KEY (order_id) REFERENCES orders(order_id),
 CHECK (amount > 0)
) ENGINE=InnoDB;

CREATE TABLE parts (
 part_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 part_name VARCHAR(150) NOT NULL,
 category VARCHAR(80), unit VARCHAR(30) NOT NULL DEFAULT 'pcs',
 quantity_in_stock INT UNSIGNED NOT NULL DEFAULT 0,
 minimum_stock INT UNSIGNED NOT NULL DEFAULT 0,
 standard_unit_cost DECIMAL(12,2) NOT NULL DEFAULT 0,
 UNIQUE KEY uq_part_name (part_name),
 CHECK (standard_unit_cost >= 0)
) ENGINE=InnoDB;

CREATE TABLE project_parts (
 project_id BIGINT UNSIGNED NOT NULL,
 part_id BIGINT UNSIGNED NOT NULL,
 quantity_required INT UNSIGNED NOT NULL,
 PRIMARY KEY (project_id, part_id),
 CONSTRAINT fk_bom_project FOREIGN KEY (project_id) REFERENCES projects(project_id),
 CONSTRAINT fk_bom_part FOREIGN KEY (part_id) REFERENCES parts(part_id),
 CHECK (quantity_required > 0)
) ENGINE=InnoDB;

CREATE TABLE suppliers (
 supplier_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 supplier_name VARCHAR(150) NOT NULL,
 phone VARCHAR(20), email VARCHAR(150), address TEXT
) ENGINE=InnoDB;

CREATE TABLE purchases (
 purchase_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 supplier_id BIGINT UNSIGNED NOT NULL,
 purchase_date DATE NOT NULL,
 status ENUM('ORDERED','RECEIVED','CANCELLED') NOT NULL DEFAULT 'ORDERED',
 notes TEXT,
 CONSTRAINT fk_purchase_supplier FOREIGN KEY (supplier_id) REFERENCES suppliers(supplier_id)
) ENGINE=InnoDB;

CREATE TABLE purchase_items (
 purchase_item_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 purchase_id BIGINT UNSIGNED NOT NULL,
 part_id BIGINT UNSIGNED NOT NULL,
 quantity INT UNSIGNED NOT NULL,
 unit_cost DECIMAL(12,2) NOT NULL,
 CONSTRAINT fk_pi_purchase FOREIGN KEY (purchase_id) REFERENCES purchases(purchase_id),
 CONSTRAINT fk_pi_part FOREIGN KEY (part_id) REFERENCES parts(part_id),
 CHECK (quantity > 0), CHECK (unit_cost >= 0)
) ENGINE=InnoDB;

CREATE TABLE stock_movements (
 movement_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 part_id BIGINT UNSIGNED NOT NULL,
 movement_type ENUM('PURCHASE','CONSUMPTION','ADJUSTMENT_IN','ADJUSTMENT_OUT','RETURN') NOT NULL,
 quantity_change INT NOT NULL,
 purchase_item_id BIGINT UNSIGNED NULL,
 order_item_id BIGINT UNSIGNED NULL,
 notes VARCHAR(255),
 moved_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CONSTRAINT fk_sm_part FOREIGN KEY (part_id) REFERENCES parts(part_id),
 CONSTRAINT fk_sm_pi FOREIGN KEY (purchase_item_id) REFERENCES purchase_items(purchase_item_id),
 CONSTRAINT fk_sm_oi FOREIGN KEY (order_item_id) REFERENCES order_items(order_item_id),
 CHECK (quantity_change <> 0),
 CHECK ((movement_type IN ('PURCHASE','ADJUSTMENT_IN','RETURN') AND quantity_change > 0)
     OR (movement_type IN ('CONSUMPTION','ADJUSTMENT_OUT') AND quantity_change < 0)),
 INDEX idx_sm_part_time (part_id, moved_at)
) ENGINE=InnoDB;

CREATE TABLE expenses (
 expense_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 order_id BIGINT UNSIGNED NULL,
 expense_date DATE NOT NULL,
 category VARCHAR(80) NOT NULL,
 description VARCHAR(255),
 amount DECIMAL(12,2) NOT NULL,
 CONSTRAINT fk_expense_order FOREIGN KEY (order_id) REFERENCES orders(order_id),
 CHECK (amount > 0)
) ENGINE=InnoDB;

CREATE OR REPLACE VIEW v_order_balances AS
SELECT o.order_id, c.full_name AS customer_name, o.status,
 COALESCE(i.order_total,0) AS order_total,
 COALESCE(p.amount_paid,0) AS amount_paid,
 COALESCE(i.order_total,0)-COALESCE(p.amount_paid,0) AS pending_amount
FROM orders o JOIN customers c ON c.customer_id=o.customer_id
LEFT JOIN (SELECT order_id, SUM(quantity*unit_price) order_total FROM order_items GROUP BY order_id) i ON i.order_id=o.order_id
LEFT JOIN (SELECT order_id, SUM(amount) amount_paid FROM payments GROUP BY order_id) p ON p.order_id=o.order_id;

CREATE OR REPLACE VIEW v_low_stock AS
SELECT part_id,part_name,quantity_in_stock,minimum_stock
FROM parts WHERE quantity_in_stock <= minimum_stock;

DELIMITER $$
CREATE TRIGGER trg_stock_movement_before_insert
BEFORE INSERT ON stock_movements FOR EACH ROW
BEGIN
 DECLARE v_qty INT UNSIGNED;
 SELECT quantity_in_stock INTO v_qty FROM parts WHERE part_id=NEW.part_id FOR UPDATE;
 IF v_qty + NEW.quantity_change < 0 THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Insufficient stock';
 END IF;
 UPDATE parts SET quantity_in_stock=quantity_in_stock+NEW.quantity_change WHERE part_id=NEW.part_id;
END$$

CREATE TRIGGER trg_stock_movement_no_update
BEFORE UPDATE ON stock_movements FOR EACH ROW
BEGIN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Stock movements are immutable; insert a reversing movement';
END$$

CREATE TRIGGER trg_stock_movement_no_delete
BEFORE DELETE ON stock_movements FOR EACH ROW
BEGIN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Stock movements cannot be deleted';
END$$

CREATE PROCEDURE receive_purchase(IN p_purchase_id BIGINT UNSIGNED)
BEGIN
 DECLARE v_status VARCHAR(20);
 DECLARE v_count INT;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 START TRANSACTION;
 SELECT status INTO v_status FROM purchases WHERE purchase_id=p_purchase_id FOR UPDATE;
 IF v_status IS NULL OR v_status <> 'ORDERED' THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Purchase is missing or not ORDERED';
 END IF;
 SELECT COUNT(*) INTO v_count FROM purchase_items WHERE purchase_id=p_purchase_id;
 IF v_count=0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Purchase has no items'; END IF;
 INSERT INTO stock_movements(part_id,movement_type,quantity_change,purchase_item_id,notes)
 SELECT part_id,'PURCHASE',quantity,purchase_item_id,CONCAT('Received purchase ',p_purchase_id)
 FROM purchase_items WHERE purchase_id=p_purchase_id ORDER BY part_id;
 UPDATE purchases SET status='RECEIVED' WHERE purchase_id=p_purchase_id;
 COMMIT;
END$$
DELIMITER ;

-- Business rules to enforce in Python services:
-- 1. Lock the order row and check total payments before inserting another payment.
-- 2. Prevent edits to order items after component consumption or delivery.
-- 3. For assembly, lock the order and component rows in a consistent part_id order,
--    check available quantities, then insert negative CONSUMPTION stock movements.
-- 4. Record consumption only once per order item, in a single transaction.
-- 5. Calculate historical job cost using consumption-time costs rather than today's standard cost.
-- 6. Restrict application DB credentials to the minimum necessary privileges.


-- ================= PRELOADED DEMONSTRATION DATA =================
-- ProjectHub demonstration dataset. All customer/supplier identities are fictional.
-- Run once after the schema has been created. The schema's stock trigger maintains balances.

INSERT INTO customers (customer_id,full_name,phone,email,notes) VALUES
(1,'Aarav Sharma','9876501001','aarav.sharma@example.com','College student; electronics project order'),
(2,'Mehak Arora','9876501002','mehak.arora@example.com','Engineering student'),
(3,'Rohan Verma','9876501003','rohan.verma@example.com','Repeat customer'),
(4,'Simran Kaur','9876501004','simran.kaur@example.com','Requested demonstration before delivery'),
(5,'Kabir Singh','9876501005','kabir.singh@example.com','Group project purchase'),
(6,'Ananya Gupta','9876501006','ananya.gupta@example.com','Urgent delivery requested'),
(7,'Dev Malhotra','9876501007','dev.malhotra@example.com','Final-year project'),
(8,'Ishita Jain','9876501008','ishita.jain@example.com','Repeat customer');

INSERT INTO projects (project_id,project_name,description,default_selling_price) VALUES
(1,'LiFi Text Communication System','One-way visible-light text communication using two Arduino boards.',1800.00),
(2,'Temperature-Controlled DC Motor','DHT11-based temperature control of a hobby DC motor using a MOSFET.',1300.00),
(3,'Capacitor Charging and Discharging','Demonstration board showing capacitor charge/discharge behaviour with LEDs and push button.',950.00),
(4,'Automatic Dustbin','Ultrasonic sensor detects a nearby object and operates an SG90 servo lid.',1100.00),
(5,'Water Quality Monitoring System','TDS sensor with Arduino and 16x2 LCD readout.',1450.00),
(6,'Smart Attendance System','ESP32, RFID reader and LCD-based attendance prototype.',2200.00),
(7,'Automatic Street Light','LDR-based automatic LED switching circuit.',650.00),
(8,'Obstacle Avoidance Robot','Four-wheel robot using ultrasonic obstacle detection.',2500.00);

INSERT INTO parts (part_id,part_name,category,unit,quantity_in_stock,minimum_stock,standard_unit_cost) VALUES
(1,'Arduino UNO compatible board','Controller','pcs',0,2,250.00),
(2,'ESP32 development board','Controller','pcs',0,2,380.00),
(3,'DHT11 temperature sensor','Sensor','pcs',0,3,60.00),
(4,'LDR photoresistor','Sensor','pcs',0,5,10.00),
(5,'HC-SR04 ultrasonic sensor','Sensor','pcs',0,3,75.00),
(6,'SG90 micro servo','Actuator','pcs',0,2,100.00),
(7,'16x2 LCD with I2C module','Display','pcs',0,2,150.00),
(8,'RC522 RFID reader module','Module','pcs',0,2,100.00),
(9,'DC hobby motor 3-6V','Motor','pcs',0,4,55.00),
(10,'IRLZ44N MOSFET','Semiconductor','pcs',0,3,45.00),
(11,'Breadboard','Prototyping','pcs',0,4,60.00),
(12,'Jumper wire set','Wiring','set',0,3,45.00),
(13,'10k ohm resistor','Passive','pcs',0,20,1.00),
(14,'220 ohm resistor','Passive','pcs',0,20,1.00),
(15,'Red LED','Indicator','pcs',0,15,2.00),
(16,'Green LED','Indicator','pcs',0,15,2.00),
(17,'470 uF capacitor','Passive','pcs',0,5,8.00),
(18,'Push button','Input','pcs',0,10,3.00),
(19,'BPW34 photodiode alternative receiver module','Sensor','pcs',0,2,85.00),
(20,'L298N motor driver','Motor driver','pcs',0,2,120.00),
(21,'4WD robot chassis with wheels','Mechanical','set',0,1,280.00),
(22,'TDS sensor module','Sensor','pcs',0,2,220.00),
(23,'9V battery clip and connector','Power','pcs',0,5,12.00),
(24,'5V breadboard power module','Power','pcs',0,2,65.00),
(25,'RC/IR receiver module','Sensor','pcs',0,2,40.00);

INSERT INTO project_parts(project_id,part_id,quantity_required) VALUES
-- LiFi
(1,1,2),(1,11,1),(1,12,1),(1,14,2),(1,15,1),(1,16,1),(1,19,1),
-- Temperature-controlled motor
(2,1,1),(2,3,1),(2,9,1),(2,10,1),(2,11,1),(2,13,2),(2,23,1),
-- Capacitor demonstration
(3,1,1),(3,11,1),(3,13,2),(3,14,2),(3,15,2),(3,16,2),(3,17,1),(3,18,1),
-- Automatic dustbin
(4,1,1),(4,5,1),(4,6,1),(4,11,1),(4,12,1),
-- Water quality
(5,1,1),(5,7,1),(5,11,1),(5,12,1),(5,22,1),
-- Attendance
(6,2,1),(6,7,1),(6,8,1),(6,11,1),(6,12,1),
-- Street light
(7,1,1),(7,4,1),(7,14,1),(7,15,2),(7,11,1),
-- Robot
(8,1,1),(8,5,1),(8,20,1),(8,21,1),(8,9,4),(8,11,1),(8,12,1);

INSERT INTO suppliers(supplier_id,supplier_name,phone,email,address) VALUES
(1,'CircuitKart Components','9811102001','sales@circuitkart.example','New Delhi, India'),
(2,'ElectroParts Wholesale','9811102002','orders@electroparts.example','Chandigarh, India'),
(3,'MakerSupply Hub','9811102003','support@makersupply.example','Ludhiana, India'),
(4,'Robotics Corner','9811102004','sales@roboticscorner.example','Mohali, India');

-- Parts start at zero. Receiving purchases below creates stock movement records
-- and the trigger updates the parts.quantity_in_stock balance automatically.
INSERT INTO purchases(purchase_id,supplier_id,purchase_date,status,notes) VALUES
(1,1,'2026-09-05','ORDERED','Initial controller and sensor restock'),
(2,2,'2026-09-18','ORDERED','Passive components and prototyping supplies'),
(3,3,'2026-10-02','ORDERED','Motors, displays and modules'),
(4,4,'2026-10-18','ORDERED','Robot and actuator supplies');

INSERT INTO purchase_items(purchase_item_id,purchase_id,part_id,quantity,unit_cost) VALUES
(1,1,1,12,245.00),(2,1,2,5,370.00),(3,1,3,10,58.00),(4,1,4,25,8.00),(5,1,5,8,70.00),(6,1,8,5,95.00),(7,1,22,4,210.00),(8,1,19,4,80.00),
(9,2,11,15,55.00),(10,2,12,20,40.00),(11,2,13,100,0.80),(12,2,14,100,0.80),(13,2,15,60,1.50),(14,2,16,60,1.50),(15,2,17,20,7.00),(16,2,18,40,2.50),
(17,3,7,8,140.00),(18,3,9,15,50.00),(19,3,10,10,42.00),(20,3,20,5,110.00),(21,3,23,20,10.00),(22,3,24,5,60.00),(23,3,25,5,35.00),
(24,4,6,8,90.00),(25,4,21,3,260.00);

CALL receive_purchase(1);
CALL receive_purchase(2);
CALL receive_purchase(3);
CALL receive_purchase(4);

INSERT INTO orders(order_id,customer_id,order_date,due_date,status,notes) VALUES
(1,1,'2026-09-10','2026-09-17','DELIVERED','LiFi communication project; demonstrated serial monitor output'),
(2,2,'2026-09-12','2026-09-20','DELIVERED','Temperature-controlled DC motor prototype'),
(3,3,'2026-09-20','2026-09-27','DELIVERED','Capacitor charging and discharging demonstration'),
(4,4,'2026-09-25','2026-10-05','READY','Automatic dustbin assembled; awaiting pickup'),
(5,5,'2026-10-01','2026-10-12','IN_PROGRESS','Water quality monitoring project'),
(6,6,'2026-10-05','2026-10-20','PENDING','Smart attendance system; advance received'),
(7,7,'2026-10-08','2026-10-15','DELIVERED','Automatic street light project'),
(8,8,'2026-10-11','2026-10-25','IN_PROGRESS','Obstacle avoidance robot'),
(9,1,'2026-10-15','2026-10-22','DELIVERED','Second order: capacitor demonstration board'),
(10,2,'2026-10-19','2026-10-29','PENDING','LiFi project for lab demonstration'),
(11,3,'2026-10-22','2026-10-30','CANCELLED','Order cancelled before assembly'),
(12,4,'2026-10-24','2026-11-04','PENDING','Temperature-controlled motor project'),
(13,5,'2026-10-27','2026-11-06','IN_PROGRESS','Automatic dustbin for group project'),
(14,6,'2026-10-29','2026-11-08','PENDING','Street light prototype'),
(15,7,'2026-10-31','2026-11-10','PENDING','Capacitor charging and discharging board');

INSERT INTO order_items(order_item_id,order_id,project_id,quantity,unit_price) VALUES
(1,1,1,1,1800.00),(2,2,2,1,1300.00),(3,3,3,1,950.00),(4,4,4,1,1100.00),(5,5,5,1,1450.00),
(6,6,6,1,2200.00),(7,7,7,1,650.00),(8,8,8,1,2500.00),(9,9,3,1,900.00),(10,10,1,1,1750.00),
(11,11,4,1,1050.00),(12,12,2,1,1300.00),(13,13,4,1,1100.00),(14,14,7,2,625.00),(15,15,3,1,950.00);

INSERT INTO payments(payment_id,order_id,paid_at,amount,method,reference_no) VALUES
(1,1,'2026-09-10 12:00:00',900.00,'UPI','DEMO-UPI-001'),(2,1,'2026-09-16 17:00:00',900.00,'CASH','DEMO-CASH-001'),
(3,2,'2026-09-12 13:00:00',500.00,'UPI','DEMO-UPI-002'),(4,2,'2026-09-19 16:00:00',800.00,'CASH','DEMO-CASH-002'),
(5,3,'2026-09-20 11:00:00',950.00,'UPI','DEMO-UPI-003'),(6,4,'2026-09-25 14:00:00',500.00,'UPI','DEMO-UPI-004'),
(7,5,'2026-10-01 10:00:00',700.00,'UPI','DEMO-UPI-005'),(8,6,'2026-10-05 12:00:00',1000.00,'BANK_TRANSFER','DEMO-BANK-001'),
(9,7,'2026-10-08 15:00:00',650.00,'CASH','DEMO-CASH-003'),(10,8,'2026-10-11 11:00:00',1000.00,'UPI','DEMO-UPI-006'),
(11,9,'2026-10-15 13:00:00',900.00,'UPI','DEMO-UPI-007'),(12,10,'2026-10-19 10:00:00',500.00,'UPI','DEMO-UPI-008'),
(13,12,'2026-10-24 16:00:00',400.00,'CASH','DEMO-CASH-004'),(14,13,'2026-10-27 12:00:00',600.00,'UPI','DEMO-UPI-009'),
(15,14,'2026-10-29 15:00:00',300.00,'UPI','DEMO-UPI-010');

-- Consume BOM quantities for orders already in assembly, ready or delivered.
-- This creates a traceable negative stock movement for each order-item component.
INSERT INTO stock_movements(part_id,movement_type,quantity_change,order_item_id,notes)
SELECT pp.part_id,'CONSUMPTION',-(pp.quantity_required * oi.quantity),oi.order_item_id,
       CONCAT('Demo assembly consumption for order ',oi.order_id)
FROM order_items oi
JOIN orders o ON o.order_id=oi.order_id
JOIN project_parts pp ON pp.project_id=oi.project_id
WHERE o.status IN ('IN_PROGRESS','READY','DELIVERED')
ORDER BY oi.order_item_id,pp.part_id;

INSERT INTO expenses(expense_id,order_id,expense_date,category,description,amount) VALUES
(1,1,'2026-09-10','Packaging','Protective packaging for LiFi kit',35.00),
(2,2,'2026-09-12','Transport','Local component collection',50.00),
(3,3,'2026-09-20','Packaging','Project board packaging',25.00),
(4,4,'2026-09-25','Miscellaneous','Connectors and soldering consumables',40.00),
(5,5,'2026-10-01','Transport','Supplier pickup',60.00),
(6,7,'2026-10-08','Packaging','Street light project packaging',20.00),
(7,8,'2026-10-11','Miscellaneous','Additional wiring and fasteners',85.00),
(8,9,'2026-10-15','Packaging','Capacitor project packaging',25.00),
(9,NULL,'2026-10-20','Tools','Solder and general workshop consumables',180.00),
(10,13,'2026-10-27','Transport','Delivery travel estimate',45.00);

-- Sanity checks: should return 15 orders, 8 customers, 25 parts and no negative stock.
SELECT 'customers' AS record_type,COUNT(*) AS total FROM customers
UNION ALL SELECT 'projects',COUNT(*) FROM projects
UNION ALL SELECT 'orders',COUNT(*) FROM orders
UNION ALL SELECT 'parts',COUNT(*) FROM parts
UNION ALL SELECT 'payments',COUNT(*) FROM payments
UNION ALL SELECT 'stock_movements',COUNT(*) FROM stock_movements;

SELECT * FROM v_order_balances ORDER BY order_id;
SELECT * FROM v_low_stock ORDER BY part_name;
