---
type: request
repos: []
---

# Original Request: Visual Diff

Implement a visual diff application based on `spec.md`:

1. Two panes, left and right.
2. Colors: follow industry standard.
3. Separator in the middle must have: arrow to copy changes to the left, to the right.
4. Both panes are plaintext and editable.
5. Find and replace functionality.
6. Synchronized scrolling: If scrolled down or up on either one, the other moves accordingly. If scrolled left or right, the other scrolls sideways accordingly.
7. Show stats of how many changes found; if no changes found, display "files identical".
8. Show invisible characters as an option (checkbox in middle pane); must be very dim, but still visible.

## Source Pointers

- `spec.md`
