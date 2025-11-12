;; VoiceBlaze DAO Governance Platform
;; Revolutionary reputation-weighted liquid democracy with AI-assisted skill matching

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-already-voted (err u104))
(define-constant err-proposal-closed (err u105))
(define-constant err-insufficient-reputation (err u106))
(define-constant err-invalid-committee (err u107))

;; Data Variables
(define-data-var proposal-nonce uint u0)
(define-data-var committee-nonce uint u0)
(define-data-var min-reputation-threshold uint u100)

;; Data Maps
(define-map members 
    principal 
    {
        reputation-score: uint,
        total-votes: uint,
        successful-votes: uint,
        domains: (list 10 (string-ascii 50)),
        active: bool
    }
)

(define-map proposals
    uint
    {
        proposer: principal,
        title: (string-utf8 100),
        description: (string-utf8 500),
        proposal-type: (string-ascii 30),
        funding-amount: uint,
        committee-id: uint,
        votes-for: uint,
        votes-against: uint,
        status: (string-ascii 20),
        created-at: uint,
        execution-block: uint,
        milestone-count: uint,
        milestones-completed: uint
    }
)

(define-map committees
    uint
    {
        name: (string-utf8 100),
        domain: (string-ascii 50),
        members: (list 20 principal),
        min-reputation: uint,
        active: bool,
        created-at: uint
    }
)

(define-map votes
    {proposal-id: uint, voter: principal}
    {
        vote-weight: uint,
        vote-type: bool,
        timestamp: uint
    }
)

(define-map delegations
    {delegator: principal, domain: (string-ascii 50)}
    {
        delegate: principal,
        active: bool
    }
)

(define-map member-endorsements
    {endorser: principal, endorsed: principal}
    {
        domain: (string-ascii 50),
        weight: uint,
        timestamp: uint
    }
)

(define-map proposal-milestones
    {proposal-id: uint, milestone-id: uint}
    {
        description: (string-utf8 200),
        funding-percentage: uint,
        completed: bool,
        verified-by: (optional principal)
    }
)

(define-map dissent-forks
    {original-proposal: uint, fork-id: uint}
    {
        forker: principal,
        resource-allocation: uint,
        new-proposal-id: uint,
        created-at: uint
    }
)

;; Read-only functions
(define-read-only (get-member (member principal))
    (map-get? members member)
)

(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals proposal-id)
)

(define-read-only (get-committee (committee-id uint))
    (map-get? committees committee-id)
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
    (map-get? votes {proposal-id: proposal-id, voter: voter})
)

(define-read-only (get-delegation (delegator principal) (domain (string-ascii 50)))
    (map-get? delegations {delegator: delegator, domain: domain})
)

(define-read-only (get-member-reputation (member principal))
    (match (map-get? members member)
        member-data (ok (get reputation-score member-data))
        (err err-not-found)
    )
)

(define-read-only (get-proposal-status (proposal-id uint))
    (match (map-get? proposals proposal-id)
        proposal-data (ok (get status proposal-data))
        (err err-not-found)
    )
)

(define-read-only (calculate-vote-weight (voter principal))
    (match (map-get? members voter)
        member-data 
            (let 
                (
                    (base-weight (get reputation-score member-data))
                    (success-rate (if (> (get total-votes member-data) u0)
                        (/ (* (get successful-votes member-data) u100) (get total-votes member-data))
                        u0))
                )
                (ok (+ base-weight (/ (* base-weight success-rate) u100)))
            )
        (err err-not-found)
    )
)

;; Public functions
(define-public (register-member (domains (list 10 (string-ascii 50))))
    (let
        (
            (caller tx-sender)
        )
        (asserts! (is-none (map-get? members caller)) (err u108))
        (ok (map-set members caller {
            reputation-score: u50,
            total-votes: u0,
            successful-votes: u0,
            domains: domains,
            active: true
        }))
    )
)

(define-public (create-committee 
    (name (string-utf8 100))
    (domain (string-ascii 50))
    (committee-members (list 20 principal))
    (min-reputation uint)
)
    (let
        (
            (committee-id (+ (var-get committee-nonce) u1))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set committee-nonce committee-id)
        (ok (map-set committees committee-id {
            name: name,
            domain: domain,
            members: committee-members,
            min-reputation: min-reputation,
            active: true,
            created-at: block-height
        }))
    )
)

(define-public (submit-proposal
    (title (string-utf8 100))
    (description (string-utf8 500))
    (proposal-type (string-ascii 30))
    (funding-amount uint)
    (committee-id uint)
    (milestone-count uint)
)
    (let
        (
            (proposal-id (+ (var-get proposal-nonce) u1))
            (member-data (unwrap! (map-get? members tx-sender) err-not-found))
        )
        (asserts! (get active member-data) err-unauthorized)
        (asserts! (>= (get reputation-score member-data) (var-get min-reputation-threshold)) err-insufficient-reputation)
        (asserts! (is-some (map-get? committees committee-id)) err-invalid-committee)
        (var-set proposal-nonce proposal-id)
        (ok (map-set proposals proposal-id {
            proposer: tx-sender,
            title: title,
            description: description,
            proposal-type: proposal-type,
            funding-amount: funding-amount,
            committee-id: committee-id,
            votes-for: u0,
            votes-against: u0,
            status: "active",
            created-at: block-height,
            execution-block: u0,
            milestone-count: milestone-count,
            milestones-completed: u0
        }))
    )
)

(define-public (cast-vote (proposal-id uint) (vote-for bool))
    (let
        (
            (voter tx-sender)
            (proposal-data (unwrap! (map-get? proposals proposal-id) err-not-found))
            (member-data (unwrap! (map-get? members voter) err-not-found))
            (vote-weight (unwrap! (calculate-vote-weight voter) err-not-found))
        )
        (asserts! (is-eq (get status proposal-data) "active") err-proposal-closed)
        (asserts! (is-none (map-get? votes {proposal-id: proposal-id, voter: voter})) err-already-voted)
        (asserts! (get active member-data) err-unauthorized)
        
        (map-set votes {proposal-id: proposal-id, voter: voter} {
            vote-weight: vote-weight,
            vote-type: vote-for,
            timestamp: block-height
        })
        
        (map-set proposals proposal-id 
            (merge proposal-data {
                votes-for: (if vote-for (+ (get votes-for proposal-data) vote-weight) (get votes-for proposal-data)),
                votes-against: (if vote-for (get votes-against proposal-data) (+ (get votes-against proposal-data) vote-weight))
            })
        )
        
        (map-set members voter
            (merge member-data {
                total-votes: (+ (get total-votes member-data) u1)
            })
        )
        
        (ok true)
    )
)

(define-public (delegate-vote (domain (string-ascii 50)) (delegate principal))
    (let
        (
            (delegator tx-sender)
            (delegate-data (unwrap! (map-get? members delegate) err-not-found))
        )
        (asserts! (get active delegate-data) err-unauthorized)
        (ok (map-set delegations {delegator: delegator, domain: domain} {
            delegate: delegate,
            active: true
        }))
    )
)

(define-public (endorse-member (endorsed principal) (domain (string-ascii 50)) (weight uint))
    (let
        (
            (endorser tx-sender)
            (endorser-data (unwrap! (map-get? members endorser) err-not-found))
            (endorsed-data (unwrap! (map-get? members endorsed) err-not-found))
        )
        (asserts! (get active endorser-data) err-unauthorized)
        (asserts! (get active endorsed-data) err-unauthorized)
        (asserts! (<= weight (get reputation-score endorser-data)) err-invalid-amount)
        
        (map-set member-endorsements {endorser: endorser, endorsed: endorsed} {
            domain: domain,
            weight: weight,
            timestamp: block-height
        })
        
        (ok (map-set members endorsed
            (merge endorsed-data {
                reputation-score: (+ (get reputation-score endorsed-data) (/ weight u10))
            })
        ))
    )
)

(define-public (complete-milestone (proposal-id uint) (milestone-id uint))
    (let
        (
            (proposal-data (unwrap! (map-get? proposals proposal-id) err-not-found))
            (milestone-data (unwrap! (map-get? proposal-milestones {proposal-id: proposal-id, milestone-id: milestone-id}) err-not-found))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (not (get completed milestone-data)) (err u109))
        
        (map-set proposal-milestones {proposal-id: proposal-id, milestone-id: milestone-id}
            (merge milestone-data {
                completed: true,
                verified-by: (some tx-sender)
            })
        )
        
        (ok (map-set proposals proposal-id
            (merge proposal-data {
                milestones-completed: (+ (get milestones-completed proposal-data) u1)
            })
        ))
    )
)

(define-public (create-dissent-fork (original-proposal uint) (resource-percentage uint))
    (let
        (
            (fork-id u1)
            (proposal-data (unwrap! (map-get? proposals original-proposal) err-not-found))
            (forker tx-sender)
            (forker-data (unwrap! (map-get? members forker) err-not-found))
        )
        (asserts! (get active forker-data) err-unauthorized)
        (asserts! (<= resource-percentage u100) err-invalid-amount)
        
        (ok (map-set dissent-forks {original-proposal: original-proposal, fork-id: fork-id} {
            forker: forker,
            resource-allocation: (/ (* (get funding-amount proposal-data) resource-percentage) u100),
            new-proposal-id: (+ (var-get proposal-nonce) u1),
            created-at: block-height
        }))
    )
)

(define-public (update-member-reputation (member principal) (new-reputation uint))
    (let
        (
            (member-data (unwrap! (map-get? members member) err-not-found))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-set members member
            (merge member-data {
                reputation-score: new-reputation
            })
        ))
    )
)

(define-public (close-proposal (proposal-id uint))
    (let
        (
            (proposal-data (unwrap! (map-get? proposals proposal-id) err-not-found))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-eq (get status proposal-data) "active") err-proposal-closed)
        
        (ok (map-set proposals proposal-id
            (merge proposal-data {
                status: (if (> (get votes-for proposal-data) (get votes-against proposal-data)) "approved" "rejected"),
                execution-block: block-height
            })
        ))
    )
)

;; Initialize contract
(begin
    (map-set members contract-owner {
        reputation-score: u1000,
        total-votes: u0,
        successful-votes: u0,
        domains: (list "governance" "technical" "finance"),
        active: true
    })
)