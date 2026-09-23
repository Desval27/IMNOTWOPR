# Mechanical Design Notes

These notes define the revised PCB, front-panel, and backplane specifications, using 4 HP (20.32 mm) card spacing. The KiCad layouts are pending updates to match this specification; see [Layout Updates Pending](#layout-updates-pending).

## PCB and Front-Panel Specifications

The mechanical design uses a simplified interpretation of IEC 60297-3-101. The original reference is this [system explanation](https://www.scribd.com/document/53335543/IEC-60297-3-101-system-explanation), rather than the standard itself. The closest configuration is an unshielded plug-in unit with static cantilever handles. Handle mounting holes are omitted for appearance but can be added if needed.

- **Card cage:** SCHROFF [24564-131](https://www.nvent.com/en-us/schroff/products/enc24564-131), a 3U, 84 HP, 175 mm-deep subrack for 160 mm cards, with rear L-ST rails, threaded inserts, and insulation strips.
- **Card size:** Single-height Eurocards, 160 mm deep by 100 mm high, for use in a 3U subrack.
- **PCB thickness:** 1.6 mm.
- **PCB brackets:** nVent SCHROFF [60807-011](https://www.nvent.com/en-us/schroff/products/enc60807-011) brackets attach the PCBs to the front panels using M2.5 hardware. Other brackets may work but have not been tested for this project.
- **Front-panel height:** 128.4 mm, sized for a 3U subrack.
- **Front-panel width:** The intended design uses multiples of 4 HP, where 1 HP = 5.08 mm (0.200 in). Physical panels are slightly narrower than their nominal HP allocation to provide clearance.

Typical panel widths are listed below. The physical widths match the [SCHROFF front-panel catalog](https://www.nvent.com/sites/default/files/acquiadam_assets/2023-04/7_1_schroff_cat_frontpanels_en.pdf).

| Nominal width | Allocated width | Physical panel width |
| --- | --- | --- |
| 4 HP | 20.32 mm | 20.0 mm |
| 8 HP | 40.64 mm | 40.3 mm |
| 12 HP | 60.96 mm | 60.6 mm |
| 16 HP | 81.28 mm | 80.9 mm |

Other panel widths are possible, provided they accommodate the card spacing and components. To fill an 84 HP subrack, the nominal widths of all panels, including any blanking panels, must total 84 HP.

### Bracket Mounting Holes

- **On the front panel:** Both hole centers lie 7.45 mm from the left edge, viewed from the front. The lower hole is 14.7 mm above the bottom edge. The upper hole is 99 mm above the lower hole, placing it 14.7 mm below the top edge.
- **On the PCB:** The intended hole diameter is 2.7 mm for M2.5 hardware. Both centers are specified as 3.56 mm from the front edge of the card (the left edge in the PCB template). The holes are 88.9 mm apart vertically and centered within the board's 100 mm height, leaving 5.55 mm from each hole center to the nearest top or bottom edge.

## Backplane Specifications

The backplane spans 84 HP and provides 21 connector positions at 4 HP (20.32 mm) spacing. Reserving the rightmost 4 HP position for power management leaves 20 positions for other cards. Wider cards may occupy more than one position.

The dimensions below define the revised backplane geometry, viewed from the connector side. Horizontal connector locations use the first slot pitch reference plane, not the cut PCB edge. Vertical offsets use the bottom PCB edge. Hole locations refer to their centers.

### Board Outline and Mounting Holes

| Feature | Revised dimension or location |
| --- | --- |
| Nominal 84 HP allocation | 426.72 mm (16.800 in); not the physical PCB width |
| Physical board width | 425.28 mm design target, centered on the 84 HP mounting grid |
| Board height | 128.70 mm (5.067 in) |
| Bottom mounting-hole row | 3.10 mm above the bottom edge, with the rows centered vertically |
| Top mounting-hole row | 125.60 mm above the bottom edge, with the rows centered vertically |
| Vertical mounting-hole pitch | 122.50 mm |
| Leftmost mounting-hole column | 6.90 mm from the left PCB edge; second rail-grid hole from the left |
| Rightmost mounting-hole column | 418.38 mm from the left PCB edge (6.90 mm from the right); second rail-grid hole from the right |

The centered-row calculation is (128.70 - 122.50) / 2 = 3.10 mm. The former 120.00 mm pitch and 4.35 mm edge margins are superseded. Intermediate mounting-hole columns are not specified here.

On the project's SCHROFF card cages, the outermost rail holes at both sides secure the side panels and are unavailable for backplane mounting. Use the next hole inward at each end, a 1 HP (5.08 mm) shift. Confirm screw-head and washer clearance at these positions.

The [SCHROFF EuropacPRO catalog, pages 6.8, 6.32, and 6.35](https://may-static.de/cms/content%20links/baugruppentraeger/td_227.en.pdf) identifies the kit's rear rails and shows the 84 HP insulation strip's end-hole span as 83 x 5.08 = 421.64 mm. With the PCB centered on that grid, the occupied end holes lie (425.28 - 421.64) / 2 = 1.82 mm from each PCB side. Moving one hole inward gives 1.82 + 5.08 = 6.90 mm. These are calculated coordinates for the chosen centered outline, not dimensions quoted from a kit-specific PCB drawing.

The four outer backplane mounting-hole centers are therefore (6.90, 3.10), (6.90, 125.60), (418.38, 3.10), and (418.38, 125.60) mm, measured from the PCB's lower-left corner on the connector side. Their horizontal separation is 411.48 mm. The former 2.54 mm PCB-edge offsets are superseded.

Published references:

- [SCHROFF Design Guide, page 11, Figure 6](https://www.digikey.sg/Site/Global/Layouts/DownloadPdf.ashx?pdfUrl=044BECE460B74307A75CB81661D5BB75): 122.50 mm mounting pitch and connector offsets from pitch references. Its example board height is 128.55 mm.
- [SCHROFF VME/VME64x manual, page 15](https://www.nvent.com/sites/default/files/acquiadam_assets/2021-06/73972-103.pdf): 128.70 mm height for a 3U VME backplane. Thus 128.70 mm is a published implementation size, not the only possible 3U outline.
- [SCHROFF VME assembly drawing, page 2](https://www.nvent.com/sites/default/files/dam/73972-128.pdf): 425.28 mm width for 21 slots, calculated as 21 x 20.32 - 1.44 mm. This 6U drawing supplies the horizontal reference target; it is not a drawing of the project's 3U backplane.

### Connectors and Placement

The backplane uses DIN 41612 receptacles with 96 contacts arranged in three rows of 32, on a 2.54 mm (0.100 in) contact pitch.

The example parts recorded for this design are:

- **Backplane receptacle:** HARTING 09032966825, listed at [DigiKey](https://www.digikey.com/en/products/detail/harting/09032966825/3179780) and [Mouser](https://www.mouser.com/en/ProductDetail/HARTING/09032966825).
- **Card-mounted right-angle plug:** HARTING 09031966921, listed at [DigiKey](https://www.digikey.com/en/products/detail/harting/09031966921/3179738) and [Mouser](https://www.mouser.com/en/ProductDetail/HARTING/09031966921).

The intended placement of the first receptacle is:

| Feature | Offset from first slot pitch reference plane | Offset from bottom edge |
| --- | --- | --- |
| Lower connector mounting hole | 7.62 mm | 19.35 mm |
| Upper connector mounting hole | 7.62 mm | 109.35 mm |
| Contact row b centerline | 7.92 mm | Not specified here |

The connector mounting holes are 90.00 mm apart vertically. Contact row b lies 0.30 mm to the right of the mounting-hole centerline. Each subsequent connector is offset horizontally by 20.32 mm (4 HP, or 0.800 in).

The 19.35 mm and 109.35 mm vertical locations follow from centering the 90 mm hole pair on a 128.70 mm board. These agree with the 16.25 mm separation between each connector mounting hole and the nearest backplane mounting row in the [Amphenol-BSI 3U VME drawing](https://static6.arrow.com/aropdfconversion/5b695883d421994bda990b27afda45dd473ddf9b/vme.pdf).

The horizontal reference must be carried into the PCB layout. Centering the chosen 425.28 mm board within the 426.72 mm allocation gives an inset of 0.72 mm. The first connector's PCB-edge offsets are therefore 7.62 - 0.72 = 6.90 mm for its mounting holes and 7.92 - 0.72 = 7.20 mm for row b. For connector number n (1 through 21), add (n - 1) x 20.32 mm to these offsets. This defines the project's nominal placement; check the assembled card-guide alignment before fabrication.

## Layout Updates Pending

The revised specification returns to 4 HP card spacing. The following differences were recorded during the layout review and identify updates needed to bring the KiCad files into agreement with this specification:

| Item | Revised specification | KiCad value at review |
| --- | --- | --- |
| Backplane outline | 425.28 mm by 128.70 mm, centered on the mounting grid | 428.64 mm by 130.1905 mm |
| Backplane connectors | 21 positions at 20.32 mm (4 HP) pitch | 26 connector footprints, J1-J26, at 15.24 mm (3 HP) pitch |
| Backplane mounting-hole row pitch | 122.50 mm | 122.6109 mm |
| Backplane outer mounting-hole columns | 6.90 mm from each side edge, skipping the occupied end holes | 8.58 mm from each side edge |
| First connector mounting-hole centerline | 6.90 mm from the left PCB edge (7.62 mm from the first slot pitch reference plane) | 8.58 mm from the left edge |
| 12 HP panel width | 60.6 mm | 60.06 mm |
| PCB bracket hole offset from the front edge | 3.56 mm | 3.57 mm |

These measurements come from the [backplane layout](../system/BACKPLANE/BACKPLANE.kicad_pcb), [12 HP panel template](../panels/TEMPLATE_12HP/TEMPLATE_12HP.kicad_pcb), and [card template](../modules/TEMPLATE/TEMPLATE.kicad_pcb). The card template confirms the 160 mm by 100 mm outline, 1.6 mm thickness, 2.7 mm bracket holes, and 88.9 mm hole spacing. The panel template confirms the 128.4 mm height and the stated bracket mounting-hole positions.

The selected subrack is confirmed as 24564-131. The nominal outline and hole coordinates above combine published dimensions with the project's centered-board placement and inward mounting-hole choice. Before fabrication, confirm assembled guide alignment, screw/washer clearance, manufacturing tolerances, and connector fit. This review does not establish full IEC compliance.
