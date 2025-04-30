;; trend_governance.clar
;; 
;; This contract enables community governance of the TrendGrid platform 
;; through proposal creation and voting mechanisms. It allows token holders 
;; to participate in decision-making regarding platform improvements and policy changes.

;; Error codes
(define-constant err-unauthorized (err u100))
(define-constant err-proposal-not-found (err u101))
(define-constant err-already-voted (err u102))
(define-constant err-proposal-inactive (err u103))
(define-constant err-invalid-vote (err u104))
(define-constant err-proposal-description-too-long (err u105))
(define-constant err-insufficient-tokens (err u106))
(define-constant err-proposal-active (err u107))
(define-constant err-proposal-period-expired (err u108))

;; Constants
(define-constant proposal-duration u10080) ;; 7 days in blocks (assuming 10-minute block time)
(define-constant min-tokens-to-propose u1000000) ;; Minimum tokens required to create a proposal
(define-constant max-description-length u500) ;; Maximum length for proposal descriptions
(define-constant vote-in-favor u1)
(define-constant vote-against u2)
(define-constant vote-abstain u3)

;; Data maps and vars
;; Proposal structure
(define-map proposals
  { proposal-id: uint }
  {
    creator: principal,
    description: (string-utf8 500),
    start-block: uint,
    end-block: uint,
    votes-for: uint,
    votes-against: uint,
    votes-abstain: uint,
    executed: bool,
    passed: bool
  }
)

;; Tracks votes cast by users
(define-map votes
  { proposal-id: uint, voter: principal }
  { vote-type: uint, vote-weight: uint }
)

;; Track proposal count
(define-data-var proposal-count uint u0)

;; Principal of the token contract for checking balances and governance rights
;; This would be initialized with the actual token contract in production
(define-constant token-contract 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.trend-token)

;; Private functions
(define-private (get-token-balance (user principal))
  ;; In production, this would call the token contract to get actual balance
  ;; For now, it's a stub that returns a default value
  (contract-call? token-contract get-balance user)
)

(define-private (check-proposal-exists (proposal-id uint))
  (match (map-get? proposals { proposal-id: proposal-id })
    proposal (ok proposal)
    (err-proposal-not-found)
  )
)

(define-private (check-proposal-active (proposal-id uint))
  (match (map-get? proposals { proposal-id: proposal-id })
    proposal 
      (if (and 
            (>= block-height (get start-block proposal))
            (<= block-height (get end-block proposal))
            (not (get executed proposal))
          )
        (ok proposal)
        (err-proposal-inactive)
      )
    (err-proposal-not-found)
  )
)

(define-private (check-not-voted (proposal-id uint) (voter principal))
  (match (map-get? votes { proposal-id: proposal-id, voter: voter })
    vote-info (err-already-voted)
    (ok true)
  )
)

(define-private (is-valid-vote-type (vote-type uint))
  (or 
    (is-eq vote-type vote-in-favor)
    (is-eq vote-type vote-against)
    (is-eq vote-type vote-abstain)
  )
)

;; Read-only functions
(define-read-only (get-proposal (proposal-id uint))
  (check-proposal-exists proposal-id)
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
  (match (map-get? votes { proposal-id: proposal-id, voter: voter })
    vote-info (ok vote-info)
    (err u0)
  )
)

(define-read-only (get-proposal-count)
  (var-get proposal-count)
)

(define-read-only (can-execute-proposal (proposal-id uint))
  (match (map-get? proposals { proposal-id: proposal-id })
    proposal 
      (and 
        (> block-height (get end-block proposal))
        (not (get executed proposal))
        (> (get votes-for proposal) (get votes-against proposal))
      )
    false
  )
)

;; Public functions
;; Create a new governance proposal
(define-public (create-proposal (description (string-utf8 500)))
  (let 
    (
      (user tx-sender)
      (user-balance (get-token-balance user))
      (proposal-id (+ (var-get proposal-count) u1))
      (start-block block-height)
      (end-block (+ block-height proposal-duration))
    )
    
    ;; Check if description is too long
    (if (> (len description) max-description-length)
      (err-proposal-description-too-long)
      
      ;; Check if user has enough tokens to create proposal
      (if (< user-balance min-tokens-to-propose)
        (err-insufficient-tokens)
        
        ;; Create proposal
        (begin
          (map-set proposals
            { proposal-id: proposal-id }
            {
              creator: user,
              description: description,
              start-block: start-block,
              end-block: end-block,
              votes-for: u0,
              votes-against: u0,
              votes-abstain: u0,
              executed: false,
              passed: false
            }
          )
          (var-set proposal-count proposal-id)
          (ok proposal-id)
        )
      )
    )
  )
)

;; Cast a vote on a proposal
(define-public (vote (proposal-id uint) (vote-type uint))
  (let
    (
      (user tx-sender)
      (user-balance (get-token-balance user))
    )
    
    ;; Check if proposal exists and is active
    (match (check-proposal-active proposal-id)
      proposal
        ;; Check if vote type is valid
        (if (not (is-valid-vote-type vote-type))
          (err-invalid-vote)
          
          ;; Check if user has already voted
          (match (check-not-voted proposal-id user)
            success
              ;; Record vote
              (begin
                (map-set votes
                  { proposal-id: proposal-id, voter: user }
                  { vote-type: vote-type, vote-weight: user-balance }
                )
                
                ;; Update vote tallies
                (match vote-type
                  vote-in-favor (map-set proposals { proposal-id: proposal-id }
                                  (merge proposal { votes-for: (+ (get votes-for proposal) user-balance) }))
                  vote-against (map-set proposals { proposal-id: proposal-id }
                                  (merge proposal { votes-against: (+ (get votes-against proposal) user-balance) }))
                  vote-abstain (map-set proposals { proposal-id: proposal-id }
                                  (merge proposal { votes-abstain: (+ (get votes-abstain proposal) user-balance) }))
                  true
                )
                (ok true)
              )
            error error
          )
        )
      error error
    )
  )
)

;; Execute a passed proposal
(define-public (execute-proposal (proposal-id uint))
  (match (check-proposal-exists proposal-id)
    proposal
      ;; Check if proposal voting period has ended
      (if (<= block-height (get end-block proposal))
        (err-proposal-active)
        
        ;; Check if proposal has already been executed
        (if (get executed proposal)
          (err-proposal-inactive)
          
          ;; Check if proposal has passed (more votes for than against)
          (if (> (get votes-for proposal) (get votes-against proposal))
            (begin
              ;; Mark proposal as executed and passed
              (map-set proposals
                { proposal-id: proposal-id }
                (merge proposal { executed: true, passed: true })
              )
              ;; In a real implementation, this would trigger the actual execution logic
              ;; which might involve updating platform parameters or other contracts
              (ok true)
            )
            (begin
              ;; Mark proposal as executed but not passed
              (map-set proposals
                { proposal-id: proposal-id }
                (merge proposal { executed: true, passed: false })
              )
              (ok false)
            )
          )
        )
      )
    error error
  )
)