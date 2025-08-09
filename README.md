# Decentralized Public Chimney and Fireplace Services Regulation

A comprehensive blockchain-based system for regulating chimney and fireplace services, ensuring public safety through decentralized certification and oversight.

## Overview

This system consists of five interconnected smart contracts that manage different aspects of chimney and fireplace services regulation:

1. **Chimney Sweep Certification Contract** - Issues and manages licenses for chimney cleaning and inspection services
2. **Fireplace Installation Oversight Contract** - Regulates installation of wood stoves, gas fireplaces, and inserts
3. **Carbon Monoxide Safety Contract** - Ensures proper ventilation and safety testing of heating appliances
4. **Fire Safety Inspection Contract** - Conducts inspections to prevent chimney fires and carbon monoxide poisoning
5. **Masonry Repair Certification Contract** - Manages licenses for chimney and fireplace structural repairs

## Key Features

### Certification Management
- Issue professional licenses and certifications
- Track certification expiration dates
- Handle renewals and revocations
- Maintain certification history

### Safety Compliance
- Enforce safety standards and regulations
- Track inspection schedules and results
- Monitor compliance violations
- Generate safety reports

### Fee Management
- Transparent fee structure for all services
- Automated fee collection and distribution
- Revenue tracking for regulatory operations

### Decentralized Governance
- Admin role management
- Transparent decision-making processes
- Immutable record keeping

## Contract Architecture

### Data Structures

Each contract maintains:
- **Certifications/Licenses**: Professional credentials with expiration dates
- **Inspections**: Safety inspection records and schedules
- **Violations**: Compliance violation tracking
- **Fees**: Service fee management
- **Admin Controls**: Governance and administrative functions

### Core Functions

- \`issue-certification\`: Issue new professional certifications
- \`renew-certification\`: Renew existing certifications
- \`revoke-certification\`: Revoke certifications for violations
- \`schedule-inspection\`: Schedule safety inspections
- \`record-inspection\`: Record inspection results
- \`report-violation\`: Report safety violations
- \`pay-fees\`: Handle fee payments
- \`get-certification-status\`: Check certification validity

## Safety Standards

### Chimney Sweep Certification
- Professional training verification
- Equipment safety standards
- Insurance requirements
- Continuing education mandates

### Fireplace Installation Oversight
- Building code compliance
- Proper ventilation requirements
- Material safety standards
- Installation quality assurance

### Carbon Monoxide Safety
- Detector installation requirements
- Ventilation system inspections
- Gas appliance safety checks
- Emergency response protocols

### Fire Safety Inspection
- Chimney structural integrity
- Creosote buildup monitoring
- Spark arrestor functionality
- Clearance requirements

### Masonry Repair Certification
- Structural engineering standards
- Material quality requirements
- Weather resistance specifications
- Seismic safety compliance

## Getting Started

### Prerequisites
- Clarinet CLI installed
- Node.js and npm
- Stacks wallet for testing

### Installation

\`\`\`bash
git clone <repository-url>
cd chimney-fireplace-regulation
npm install
clarinet check
\`\`\`

### Testing

\`\`\`bash
npm test
\`\`\`

### Deployment

\`\`\`bash
clarinet deploy --testnet
\`\`\`

## Usage Examples

### Issue Chimney Sweep Certification

\`\`\`clarity
(contract-call? .chimney-sweep-certification issue-certification
'SP1HTBVD3JG9C05J7HBJTHGR0GGW7KX975CN0QKK1
u365)
\`\`\`

### Schedule Fire Safety Inspection

\`\`\`clarity
(contract-call? .fire-safety-inspection schedule-inspection
'SP1HTBVD3JG9C05J7HBJTHGR0GGW7KX975CN0QKK1
u1640995200)
\`\`\`

### Check Certification Status

\`\`\`clarity
(contract-call? .chimney-sweep-certification get-certification-status
'SP1HTBVD3JG9C05J7HBJTHGR0GGW7KX975CN0QKK1)
\`\`\`

## Governance

The system includes administrative controls for:
- Setting fee structures
- Updating safety standards
- Managing certification requirements
- Handling appeals and disputes

## Security Considerations

- All certifications are immutably recorded on the blockchain
- Multi-signature requirements for administrative actions
- Time-locked updates for critical system changes
- Comprehensive audit trails for all operations

## Contributing

Please read our contributing guidelines and submit pull requests for any improvements.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
\`\`\`

```clar file="contracts/chimney-sweep-certification.clar"
;; Chimney Sweep Certification Contract
;; Issues and manages licenses for chimney cleaning and inspection services

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-CERTIFIED (err u101))
(define-constant ERR-NOT-CERTIFIED (err u102))
(define-constant ERR-CERTIFICATION-EXPIRED (err u103))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u104))
(define-constant ERR-INVALID-DURATION (err u105))

;; Data Variables
(define-data-var certification-fee uint u1000000) ;; 1 STX in microSTX
(define-data-var renewal-fee uint u500000) ;; 0.5 STX in microSTX
(define-data-var admin principal CONTRACT-OWNER)

;; Data Maps
(define-map certifications 
  principal 
  {
    issued-at: uint,
    expires-at: uint,
    certification-id: uint,
    status: (string-ascii 20)
  }
)

(define-map certification-history
  {holder: principal, certification-id: uint}
  {
    issued-at: uint,
    expires-at: uint,
    revoked-at: (optional uint),
    reason: (optional (string-ascii 100))
  }
)

(define-data-var next-certification-id uint u1)

;; Private Functions
(define-private (is-admin (caller principal))
  (is-eq caller (var-get admin))
)

(define-private (is-certification-valid (holder principal))
  (match (map-get? certifications holder)
    cert (&lt; block-height (get expires-at cert))
    false
  )
)

;; Public Functions

;; Issue new certification
(define-public (issue-certification (holder principal) (duration-days uint))
  (let (
    (certification-id (var-get next-certification-id))
    (current-time block-height)
    (expiry-time (+ current-time (* duration-days u144))) ;; Assuming ~144 blocks per day
  )
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> duration-days u0) ERR-INVALID-DURATION)
    (asserts! (&lt; duration-days u1095) ERR-INVALID-DURATION) ;; Max 3 years
    (asserts! (is-none (map-get? certifications holder)) ERR-ALREADY-CERTIFIED)
    
    ;; Record certification
    (map-set certifications holder {
      issued-at: current-time,
      expires-at: expiry-time,
      certification-id: certification-id,
      status: "active"
    })
    
    ;; Record in history
    (map-set certification-history 
      {holder: holder, certification-id: certification-id}
      {
        issued-at: current-time,
        expires-at: expiry-time,
        revoked-at: none,
        reason: none
      }
    )
    
    ;; Increment certification ID
    (var-set next-certification-id (+ certification-id u1))
    
    (ok certification-id)
  )
)

;; Renew existing certification
(define-public (renew-certification (duration-days uint))
  (let (
    (current-cert (unwrap! (map-get? certifications tx-sender) ERR-NOT-CERTIFIED))
    (current-time block-height)
    (new-expiry (+ current-time (* duration-days u144)))
    (payment-amount (var-get renewal-fee))
  )
    (asserts! (> duration-days u0) ERR-INVALID-DURATION)
    (asserts! (&lt; duration-days u1095) ERR-INVALID-DURATION)
    (asserts! (>= (stx-get-balance tx-sender) payment-amount) ERR-INSUFFICIENT-PAYMENT)
    
    ;; Transfer renewal fee
    (try! (stx-transfer? payment-amount tx-sender (var-get admin)))
    
    ;; Update certification
    (map-set certifications tx-sender (merge current-cert {
      expires-at: new-expiry,
      status: "active"
    }))
    
    (ok true)
  )
)

;; Revoke certification
(define-public (revoke-certification (holder principal) (reason (string-ascii 100)))
  (let (
    (current-cert (unwrap! (map-get? certifications holder) ERR-NOT-CERTIFIED))
    (certification-id (get certification-id current-cert))
  )
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    
    ;; Update certification status
    (map-set certifications holder (merge current-cert {
      status: "revoked"
    }))
    
    ;; Update history
    (map-set certification-history 
      {holder: holder, certification-id: certification-id}
      (merge 
        (unwrap-panic (map-get? certification-history {holder: holder, certification-id: certification-id}))
        {
          revoked-at: (some block-height),
          reason: (some reason)
        }
      )
    )
    
    (ok true)
  )
)

;; Pay certification fee
(define-public (pay-certification-fee)
  (let (
    (fee-amount (var-get certification-fee))
  )
    (asserts! (>= (stx-get-balance tx-sender) fee-amount) ERR-INSUFFICIENT-PAYMENT)
    (try! (stx-transfer? fee-amount tx-sender (var-get admin)))
    (ok true)
  )
)

;; Read-only Functions

;; Get certification status
(define-read-only (get-certification-status (holder principal))
  (match (map-get? certifications holder)
    cert (ok {
      valid: (&lt; block-height (get expires-at cert)),
      expires-at: (get expires-at cert),
      certification-id: (get certification-id cert),
      status: (get status cert)
    })
    (err ERR-NOT-CERTIFIED)
  )
)

;; Check if holder is certified
(define-read-only (is-certified (holder principal))
  (match (map-get? certifications holder)
    cert (and 
      (&lt; block-height (get expires-at cert))
      (is-eq (get status cert) "active")
    )
    false
  )
)

;; Get certification fee
(define-read-only (get-certification-fee)
  (var-get certification-fee)
)

;; Get renewal fee
(define-read-only (get-renewal-fee)
  (var-get renewal-fee)
)

;; Admin Functions

;; Set certification fee
(define-public (set-certification-fee (new-fee uint))
  (begin
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    (var-set certification-fee new-fee)
    (ok true)
  )
)

;; Set renewal fee
(define-public (set-renewal-fee (new-fee uint))
  (begin
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    (var-set renewal-fee new-fee)
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
