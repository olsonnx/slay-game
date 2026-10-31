# Painting collection

Choose **Collection** on the main menu to browse the album. Paintings unlock automatically when their artwork is revealed in an event during a game. An encounter's choice or outcome does not affect the unlock. Repeated appearances of the same painting share one slot.

Unseen paintings show a lock and hide their image, title and artist. Collected paintings show a colour thumbnail and their attribution. Select one to view the original image without the event dialog's colour treatment. **Fit** shows the whole picture; **100%** uses its original pixel dimensions. The **− / +** buttons zoom, and scroll bars allow exploring large images. Previous/Next and the left/right keys navigate collected paintings. Escape closes the viewer, then returns from the album to the main menu.

Progress is saved locally in `user://painting_collection.cfg`, independently of matches and gameplay preferences. It survives restarting the game and starting fresh matches. Discoveries begin with this feature; earlier event history is not reconstructed. This is local profile progress, without Steam achievements or cloud synchronization.

The album lists unique painting resource paths referenced by the installed event catalogue, including the common fallback painting when an event uses it. Previously collected fallback art remains visible even when no current event uses it; new albums do not gain an unreachable locked slot. New event artwork joins the album automatically. Removing an event pack can remove its paintings from the visible catalogue; saved discovery keys remain available if it returns. Unused files in the artwork directory do not create unreachable album slots.

Discovery is wired through the gameplay event dialog's reveal signal. Closing a dialog during preparation grants nothing; standalone editor previews and replay viewing do not unlock paintings. Online play records discoveries only for the player whose event dialog is actually shown. Collection changes never mutate game rules, RNG state or network snapshots.

The gallery uses small thumbnails and loads an original image only when opening the viewer. Locked slots load no artwork. The original texture is released when leaving the viewer. `tests/test_painting_collection.gd` covers unique slots, save/reload, invalid data filtering, gameplay discovery, cancelled reveals, unchanged match state, locks, full-colour/native-size display, fit, navigation and menu return behavior.

Event dialogs now crop paintings to a consistent 2:1 frame. The Collection viewer still shows the complete original. See [event artwork](event-artwork.md) for assignments, source credits and framing details.
