# Firestore Index Matrix

This document maps each paginated/filter query to the composite index defined in `firestore.indexes.json`.

## Budgets (`collectionGroup: budgets`, `queryScope: COLLECTION`)

| Query pattern | Composite index fields | Used by |
| --- | --- | --- |
| `where(status == x).orderBy(updatedAt, desc)` | `status ASC, updatedAt DESC` | `BudgetsScreen` status filter |
| `where(customerId == x).orderBy(updatedAt, desc)` | `customerId ASC, updatedAt DESC` | `BudgetsScreen` customer scope |
| `where(vehicleId == x).orderBy(updatedAt, desc)` | `vehicleId ASC, updatedAt DESC` | `BudgetsScreen` vehicle scope |
| `where(customerId == x).where(status == y).orderBy(updatedAt, desc)` | `customerId ASC, status ASC, updatedAt DESC` | `BudgetsScreen` customer + status |
| `where(vehicleId == x).where(status == y).orderBy(updatedAt, desc)` | `vehicleId ASC, status ASC, updatedAt DESC` | `BudgetsScreen` vehicle + status |
| `where(customerId == x).where(vehicleId == y).orderBy(updatedAt, desc)` | `customerId ASC, vehicleId ASC, updatedAt DESC` | `BudgetsScreen` customer + vehicle |
| `where(customerId == x).where(vehicleId == y).where(status == z).orderBy(updatedAt, desc)` | `customerId ASC, vehicleId ASC, status ASC, updatedAt DESC` | `BudgetsScreen` customer + vehicle + status |

## Repairs (`collectionGroup: repairs`, `queryScope: COLLECTION`)

| Query pattern | Composite index fields | Used by |
| --- | --- | --- |
| `where(status == x).orderBy(updatedAt, desc)` | `status ASC, updatedAt DESC` | `RepairsScreen` status filter |

## Notes

- Single-field indexes are automatically managed by Firestore and are not listed here.
- If a new filter/order combination is added, update:
  - `firestore.indexes.json`
  - this file (`firestore.indexes.md`)
