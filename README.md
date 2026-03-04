# taller_mecanico

Flutter app for workshop management (customers, vehicles, budgets, and repairs).

## Firestore setup

This repo now version-controls both Firestore rules and composite indexes:

- Rules: `firestore.rules`
- Indexes: `firestore.indexes.json`
- Index matrix: `firestore.indexes.md`
- Firebase config: `firebase.json`

## Deploy rules and indexes

From the project root:

```bash
firebase deploy --only firestore:rules,firestore:indexes
```

Or deploy only indexes:

```bash
firebase deploy --only firestore:indexes
```

## Indexes included

The current indexes cover:

- `users/{uid}/budgets` queries with:
  - `orderBy(updatedAt desc)`
  - optional filters by `status`, `customerId`, `vehicleId`
  - combined filters (`customerId + status`, `vehicleId + status`, `customerId + vehicleId`, and `customerId + vehicleId + status`)
- `users/{uid}/customers/{customerId}/vehicles/{vehicleId}/repairs` queries with:
  - `where(status == ...) + orderBy(updatedAt desc)`

These indexes support the paginated list screens introduced in:

- `lib/screens/budgets/budgets_screen.dart`
- `lib/screens/repairs/repairs_screen.dart`
