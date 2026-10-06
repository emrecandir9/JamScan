JamSCAN – low-fidelity wireframes (Sprint 1, S1-07) – revision 4
Canvas: 1152 x 2472 px = 1080 x 2400 screen (360 x 800 dp @ 3x) + phone frame
Each PSD: one named layer per UI element; "Phone frame (outline)" is the top layer.

Scan pages (01, 02a, 02b, 03, 10a-c, 12, 13, 14): profile button top right,
floating capture card (Gallery / Shutter / Library), taskbar History / Scan / Search.
All other pages: rounded taskbar Profile / Scan / Library.

Screen -> use case
01, 02a, 02b, 03   Camera, permissions, gallery import             UC-02, UC-03
04, 05             Retake prompt, loading / identifying            UC-03, UC-04
06, 07             Candidate selection, not recognised             UC-04, UC-09
08a, 08b           Manual search, no results / API error           UC-09
10a, 10b, 10c      Result overlaid on camera: auto-playing top
                   track (swipe), no previews, track dropdown      UC-06, UC-07, UC-08
11                 Learn more – full album details                 UC-08
12, 13             Save album (incl. ghost option), guest prompt   UC-10, UC-11, UC-01
14                 Scan & search history (overlay)                 UC-14
15a-c              Library: lists, empty, guest                    UC-12
16a, 16b, 17       List detail with ghost records, no results,
                   sort & filter (show owned / ghosts)             UC-12
18, 18b            Edit entry, ghost record actions                UC-13
19a, 19b, 20       New/rename list, delete confirm, bulk select    UC-13
21a, 21b           Profile, guest profile                          UC-15
22                 Login / register                                UC-01
23a, 23b           Settings, delete-account confirm                UC-15
