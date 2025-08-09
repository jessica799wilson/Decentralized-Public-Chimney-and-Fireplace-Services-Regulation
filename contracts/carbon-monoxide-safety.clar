;; Carbon Monoxide Safety Contract
;; Ensures proper ventilation and safety testing of heating appliances

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-INVALID-READING (err u301))
(define-constant ERR-UNSAFE-LEVELS (err u302))
(define-constant ERR-NOT-FOUND (err u303))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u304))
(define-constant ERR-OVERDUE-INSPECTION (err u305))

;; Data Variables
(define-data-var testing-fee uint u800000) ;; 0.8 STX in microSTX
(define-data-var emergency-response-fee uint u3000000) ;; 3 STX in microSTX
(define-data-var admin principal CONTRACT-OWNER)
(define-data-var max-safe-co-level uint u9) ;; 9 PPM maximum safe level

;; Data Maps
(define-map co-monitoring-devices
  {property-address: (string-ascii 200), device-id: uint}
  {
    owner: principal,
    installed-at: uint,
    last-tested: uint,
    device-type: (string-ascii 50),
    status: (string-ascii 20),
    battery-level: uint
  }
)

(define-map co-test-results
  uint
  {
    property-address: (string-ascii 200),
    tester: principal,
    test-date: uint,
    co-level-ppm: uint,
    ventilation-adequate: bool,
    devices-functional: bool,
    safety-status: (string-ascii 20),
    recommendations: (string-ascii 500)
  }
)

(define-map emergency-responses
  uint
  {
    property-address: (string-ascii 200),
    reported-by: principal,
    response-team: principal,
    incident-date: uint,
    co-level-detected: uint,
    evacuated: bool,
    resolved: bool,
    resolution-notes: (string-ascii 500)
  }
)

(define-map certified-testers
  principal
  {
    certified-at: uint,
    expires-at: uint,
    certification-level: (string-ascii 20),
    tests-completed: uint,
    status: (string-ascii 20)
  }
)

(define-data-var next-test-id uint u1)
(define-data-var next-device-id uint u1)
(define-data-var next-emergency-id uint u1)

;; Private Functions
(define-private (is-admin (caller principal))
  (is-eq caller (var-get admin))
)

(define-private (is-certified-tester (tester principal))
  (match (map-get? certified-testers tester)
    tester-info (and
      (< block-height (get expires-at tester-info))
      (is-eq (get status tester-info) "active")
    )
    false
  )
)

(define-private (is-safe-co-level (co-level uint))
  (<= co-level (var-get max-safe-co-level))
)

;; Public Functions

;; Register CO monitoring device
(define-public (register-co-device
  (property-address (string-ascii 200))
  (device-type (string-ascii 50))
)
  (let (
    (device-id (var-get next-device-id))
  )
    (map-set co-monitoring-devices
      {property-address: property-address, device-id: device-id}
      {
        owner: tx-sender,
        installed-at: block-height,
        last-tested: block-height,
        device-type: device-type,
        status: "active",
        battery-level: u100
      }
    )

    ;; Increment device ID
    (var-set next-device-id (+ device-id u1))

    (ok device-id)
  )
)

;; Conduct CO safety test
(define-public (conduct-co-test
  (property-address (string-ascii 200))
  (co-level-ppm uint)
  (ventilation-adequate bool)
  (devices-functional bool)
  (recommendations (string-ascii 500))
)
  (let (
    (test-id (var-get next-test-id))
    (fee-amount (var-get testing-fee))
    (safety-status (if (is-safe-co-level co-level-ppm) "safe" "unsafe"))
  )
    (asserts! (is-certified-tester tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (>= (stx-get-balance tx-sender) fee-amount) ERR-INSUFFICIENT-PAYMENT)

    ;; Check for unsafe levels
    (if (not (is-safe-co-level co-level-ppm))
      (asserts! false ERR-UNSAFE-LEVELS)
      true
    )

    ;; Transfer testing fee
    (try! (stx-transfer? fee-amount tx-sender (var-get admin)))

    ;; Record test results
    (map-set co-test-results test-id {
      property-address: property-address,
      tester: tx-sender,
      test-date: block-height,
      co-level-ppm: co-level-ppm,
      ventilation-adequate: ventilation-adequate,
      devices-functional: devices-functional,
      safety-status: safety-status,
      recommendations: recommendations
    })

    ;; Increment test ID
    (var-set next-test-id (+ test-id u1))

    (ok test-id)
  )
)

;; Report CO emergency
(define-public (report-co-emergency
  (property-address (string-ascii 200))
  (co-level-detected uint)
  (evacuated bool)
)
  (let (
    (emergency-id (var-get next-emergency-id))
    (fee-amount (var-get emergency-response-fee))
  )
    (asserts! (>= (stx-get-balance tx-sender) fee-amount) ERR-INSUFFICIENT-PAYMENT)

    ;; Transfer emergency response fee
    (try! (stx-transfer? fee-amount tx-sender (var-get admin)))

    ;; Record emergency
    (map-set emergency-responses emergency-id {
      property-address: property-address,
      reported-by: tx-sender,
      response-team: (var-get admin), ;; Default to admin, can be updated
      incident-date: block-height,
      co-level-detected: co-level-detected,
      evacuated: evacuated,
      resolved: false,
      resolution-notes: ""
    })

    ;; Increment emergency ID
    (var-set next-emergency-id (+ emergency-id u1))

    (ok emergency-id)
  )
)

;; Certify CO tester
(define-public (certify-tester
  (tester principal)
  (certification-level (string-ascii 20))
  (duration-days uint)
)
  (let (
    (expiry-time (+ block-height (* duration-days u144)))
  )
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)

    (map-set certified-testers tester {
      certified-at: block-height,
      expires-at: expiry-time,
      certification-level: certification-level,
      tests-completed: u0,
      status: "active"
    })

    (ok true)
  )
)

;; Update device battery level
(define-public (update-device-battery
  (property-address (string-ascii 200))
  (device-id uint)
  (battery-level uint)
)
  (let (
    (device (unwrap! (map-get? co-monitoring-devices {property-address: property-address, device-id: device-id}) ERR-NOT-FOUND))
  )
    (asserts! (is-eq (get owner device) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (<= battery-level u100) ERR-INVALID-READING)

    (map-set co-monitoring-devices
      {property-address: property-address, device-id: device-id}
      (merge device {
        battery-level: battery-level,
        last-tested: block-height
      })
    )

    (ok true)
  )
)

;; Resolve emergency
(define-public (resolve-emergency
  (emergency-id uint)
  (resolution-notes (string-ascii 500))
)
  (let (
    (emergency (unwrap! (map-get? emergency-responses emergency-id) ERR-NOT-FOUND))
  )
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)

    (map-set emergency-responses emergency-id (merge emergency {
      resolved: true,
      resolution-notes: resolution-notes
    }))

    (ok true)
  )
)

;; Read-only Functions

;; Get device status
(define-read-only (get-device-status (property-address (string-ascii 200)) (device-id uint))
  (map-get? co-monitoring-devices {property-address: property-address, device-id: device-id})
)

;; Get test results
(define-read-only (get-test-results (test-id uint))
  (map-get? co-test-results test-id)
)

;; Get emergency details
(define-read-only (get-emergency-details (emergency-id uint))
  (map-get? emergency-responses emergency-id)
)

;; Check tester certification
(define-read-only (get-tester-certification (tester principal))
  (map-get? certified-testers tester)
)

;; Check if tester is certified
(define-read-only (is-tester-certified (tester principal))
  (is-certified-tester tester)
)

;; Get maximum safe CO level
(define-read-only (get-max-safe-co-level)
  (var-get max-safe-co-level)
)

;; Get testing fee
(define-read-only (get-testing-fee)
  (var-get testing-fee)
)

;; Admin Functions

;; Set testing fee
(define-public (set-testing-fee (new-fee uint))
  (begin
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    (var-set testing-fee new-fee)
    (ok true)
  )
)

;; Set emergency response fee
(define-public (set-emergency-response-fee (new-fee uint))
  (begin
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    (var-set emergency-response-fee new-fee)
    (ok true)
  )
)

;; Set maximum safe CO level
(define-public (set-max-safe-co-level (new-level uint))
  (begin
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    (var-set max-safe-co-level new-level)
    (ok true)
  )
)

;; Transfer admin role
(define-public (transfer-admin (new-admin principal))
  (begin
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    (var-set admin new-admin)
    (ok true)
  )
)
