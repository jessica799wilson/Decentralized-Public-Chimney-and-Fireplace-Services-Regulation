;; Fire Safety Inspection Contract
;; Conducts inspections to prevent chimney fires and carbon monoxide poisoning

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-INVALID-INSPECTION (err u401))
(define-constant ERR-NOT-FOUND (err u402))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u403))
(define-constant ERR-OVERDUE-INSPECTION (err u404))
(define-constant ERR-INVALID-RATING (err u405))

;; Data Variables
(define-data-var inspection-fee uint u1200000) ;; 1.2 STX in microSTX
(define-data-var reinspection-fee uint u600000) ;; 0.6 STX in microSTX
(define-data-var admin principal CONTRACT-OWNER)
(define-data-var inspection-interval uint u8760) ;; ~60 days in blocks

;; Data Maps
(define-map fire-safety-inspections
  uint
  {
    property-address: (string-ascii 200),
    inspector: principal,
    inspection-date: uint,
    chimney-condition: (string-ascii 20),
    creosote-level: uint,
    structural-integrity: bool,
    ventilation-adequate: bool,
    safety-rating: uint,
    passed: bool,
    violations: (list 10 (string-ascii 100)),
    next-inspection-due: uint
  }
)

(define-map certified-inspectors
  principal
  {
    certified-at: uint,
    expires-at: uint,
    inspections-completed: uint,
    specializations: (list 5 (string-ascii 50)),
    status: (string-ascii 20)
  }
)

(define-map property-inspection-history
  (string-ascii 200)
  {
    last-inspection: uint,
    total-inspections: uint,
    violations-count: uint,
    current-safety-rating: uint,
    next-due: uint
  }
)

(define-map fire-safety-violations
  uint
  {
    property-address: (string-ascii 200),
    violation-type: (string-ascii 100),
    severity: (string-ascii 20),
    reported-date: uint,
    resolved: bool,
    resolution-date: (optional uint),
    fine-amount: uint
  }
)

(define-data-var next-inspection-id uint u1)
(define-data-var next-violation-id uint u1)

;; Private Functions
(define-private (is-admin (caller principal))
  (is-eq caller (var-get admin))
)

(define-private (is-certified-inspector (inspector principal))
  (match (map-get? certified-inspectors inspector)
    inspector-info (and
      (< block-height (get expires-at inspector-info))
      (is-eq (get status inspector-info) "active")
    )
    false
  )
)

(define-private (is-valid-safety-rating (rating uint))
  (and (>= rating u1) (<= rating u5))
)

(define-private (calculate-next-inspection-date (current-rating uint))
  (let (
    (base-interval (var-get inspection-interval))
    (rating-multiplier (if (<= current-rating u2) u1 u2))
  )
    (+ block-height (* base-interval rating-multiplier))
  )
)

;; Public Functions

;; Conduct fire safety inspection
(define-public (conduct-inspection
  (property-address (string-ascii 200))
  (chimney-condition (string-ascii 20))
  (creosote-level uint)
  (structural-integrity bool)
  (ventilation-adequate bool)
  (safety-rating uint)
  (violations (list 10 (string-ascii 100)))
)
  (let (
    (inspection-id (var-get next-inspection-id))
    (fee-amount (var-get inspection-fee))
    (passed (and structural-integrity ventilation-adequate (>= safety-rating u3)))
    (next-due (calculate-next-inspection-date safety-rating))
  )
    (asserts! (is-certified-inspector tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-valid-safety-rating safety-rating) ERR-INVALID-RATING)
    (asserts! (>= (stx-get-balance tx-sender) fee-amount) ERR-INSUFFICIENT-PAYMENT)

    ;; Transfer inspection fee
    (try! (stx-transfer? fee-amount tx-sender (var-get admin)))

    ;; Record inspection
    (map-set fire-safety-inspections inspection-id {
      property-address: property-address,
      inspector: tx-sender,
      inspection-date: block-height,
      chimney-condition: chimney-condition,
      creosote-level: creosote-level,
      structural-integrity: structural-integrity,
      ventilation-adequate: ventilation-adequate,
      safety-rating: safety-rating,
      passed: passed,
      violations: violations,
      next-inspection-due: next-due
    })

    ;; Update property history
    (map-set property-inspection-history property-address {
      last-inspection: block-height,
      total-inspections: (+ (default-to u0 (get total-inspections (map-get? property-inspection-history property-address))) u1),
      violations-count: (+ (default-to u0 (get violations-count (map-get? property-inspection-history property-address))) (len violations)),
      current-safety-rating: safety-rating,
      next-due: next-due
    })

    ;; Update inspector stats
    (let (
      (inspector-info (unwrap-panic (map-get? certified-inspectors tx-sender)))
    )
      (map-set certified-inspectors tx-sender (merge inspector-info {
        inspections-completed: (+ (get inspections-completed inspector-info) u1)
      }))
    )

    ;; Increment inspection ID
    (var-set next-inspection-id (+ inspection-id u1))

    (ok inspection-id)
  )
)

;; Report fire safety violation
(define-public (report-violation
  (property-address (string-ascii 200))
  (violation-type (string-ascii 100))
  (severity (string-ascii 20))
  (fine-amount uint)
)
  (let (
    (violation-id (var-get next-violation-id))
  )
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)

    (map-set fire-safety-violations violation-id {
      property-address: property-address,
      violation-type: violation-type,
      severity: severity,
      reported-date: block-height,
      resolved: false,
      resolution-date: none,
      fine-amount: fine-amount
    })

    ;; Increment violation ID
    (var-set next-violation-id (+ violation-id u1))

    (ok violation-id)
  )
)

;; Certify fire safety inspector
(define-public (certify-inspector
  (inspector principal)
  (duration-days uint)
  (specializations (list 5 (string-ascii 50)))
)
  (let (
    (expiry-time (+ block-height (* duration-days u144)))
  )
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)

    (map-set certified-inspectors inspector {
      certified-at: block-height,
      expires-at: expiry-time,
      inspections-completed: u0,
      specializations: specializations,
      status: "active"
    })

    (ok true)
  )
)

;; Schedule reinspection
(define-public (schedule-reinspection (property-address (string-ascii 200)))
  (let (
    (fee-amount (var-get reinspection-fee))
    (property-history (unwrap! (map-get? property-inspection-history property-address) ERR-NOT-FOUND))
  )
    (asserts! (>= (stx-get-balance tx-sender) fee-amount) ERR-INSUFFICIENT-PAYMENT)

    ;; Transfer reinspection fee
    (try! (stx-transfer? fee-amount tx-sender (var-get admin)))

    ;; Update next due date to current time (immediate reinspection)
    (map-set property-inspection-history property-address (merge property-history {
      next-due: block-height
    }))

    (ok true)
  )
)

;; Resolve violation
(define-public (resolve-violation (violation-id uint))
  (let (
    (violation (unwrap! (map-get? fire-safety-violations violation-id) ERR-NOT-FOUND))
  )
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)

    (map-set fire-safety-violations violation-id (merge violation {
      resolved: true,
      resolution-date: (some block-height)
    }))

    (ok true)
  )
)

;; Read-only Functions

;; Get inspection details
(define-read-only (get-inspection-details (inspection-id uint))
  (map-get? fire-safety-inspections inspection-id)
)

;; Get property inspection history
(define-read-only (get-property-history (property-address (string-ascii 200)))
  (map-get? property-inspection-history property-address)
)

;; Get inspector certification
(define-read-only (get-inspector-certification (inspector principal))
  (map-get? certified-inspectors inspector)
)

;; Get violation details
(define-read-only (get-violation-details (violation-id uint))
  (map-get? fire-safety-violations violation-id)
)

;; Check if inspector is certified
(define-read-only (is-inspector-certified (inspector principal))
  (is-certified-inspector inspector)
)

;; Check if property inspection is overdue
(define-read-only (is-inspection-overdue (property-address (string-ascii 200)))
  (match (map-get? property-inspection-history property-address)
    history (> block-height (get next-due history))
    true ;; No history means overdue
  )
)

;; Get inspection fee
(define-read-only (get-inspection-fee)
  (var-get inspection-fee)
)

;; Get reinspection fee
(define-read-only (get-reinspection-fee)
  (var-get reinspection-fee)
)

;; Admin Functions

;; Set inspection fee
(define-public (set-inspection-fee (new-fee uint))
  (begin
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    (var-set inspection-fee new-fee)
    (ok true)
  )
)

;; Set reinspection fee
(define-public (set-reinspection-fee (new-fee uint))
  (begin
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    (var-set reinspection-fee new-fee)
    (ok true)
  )
)

;; Set inspection interval
(define-public (set-inspection-interval (new-interval uint))
  (begin
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    (var-set inspection-interval new-interval)
    (ok true)
  )
)

;; Revoke inspector certification
(define-public (revoke-inspector (inspector principal))
  (let (
    (inspector-info (unwrap! (map-get? certified-inspectors inspector) ERR-NOT-FOUND))
  )
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)

    (map-set certified-inspectors inspector (merge inspector-info {
      status: "revoked"
    }))

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
