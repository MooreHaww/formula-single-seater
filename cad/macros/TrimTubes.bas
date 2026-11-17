Attribute VB_Name = "TrimTubes"
' ============================================================================
' TrimTubes.bas  (SolidWorks VBA macro module)
' STATUS: untested, needs the app. Every call checked against the installed
'         2026 SP2.1 interop DLLs (exact interface per variable); the trim
'         behaviour itself is only known at run time.
' ----------------------------------------------------------------------------
' What it does (one click, after BuildTubes, in cad\chassis\chassis.SLDPRT)
'   Reads the trim plan cad/frame/frame_trims.csv (written by MATLAB
'   matlab/cad/frame_trims.m: one row per node, the boundary tube(s) and the
'   tubes whose ends are cut against them) and makes one Trim/Extend feature
'   per row, named Trim_<node>, end trim with a coped cut (the tube end
'   follows the boundary tube's surface).
'   1. Checks first, changes nothing: the part, the three CSVs, the solid
'      bodies, and that every body matches exactly one tube: the body's
'      centroid lies within 12 mm of that tube's centreline segment and every
'      other tube is at least 8 mm further away (a near tie is refused).
'      The distance to the segment, not to the midpoint, is used because
'      BuildTubes' simple cut lengthens one tube at a node and shortens the
'      other, which moves a centroid up to 42 mm ALONG its own tube (first
'      trim run: 17 hoop and brace bodies missed by the midpoint match). A row whose tubes cannot all be matched is
'      reported and skipped; a row whose Trim_<node> exists is kept. If no
'      row can be made the macro stops with "Nothing was changed".
'   2. Per row: InsertWeldmentTrimFeature2 with a coped cut; if refused, a
'      plain (planar) end trim; if that is refused too the row is listed with
'      the SolidWorks error text and the macro goes on with the next row.
'      Bodies are re-read and re-matched before every row (a trim replaces
'      the bodies it cuts).
'   3. Updates the cut list, then the final message and the report file
'      cad\chassis\trim_tubes_report.txt: PASS/FAIL per row, bodies before
'      and after (a trim must not add bodies), mass before and after (must
'      drop, 38 to 46 kg), cut length after, save.
'   4. Saves the part.
'
' Repo root
'   Found by walking up from the folder of the running .swp until a folder
'   with params\car_params.txt is found. All modules can live in one project
'   (repo_macros.swp); run TrimTubes.main.
'
' v4 (after the clean rebuild: 50 trims made, 114 -> 116 bodies)
'   * Counts the bodies before and after every trim and names the trim that
'     raised the count, with the tubes and the new bodies.
'   * Stub cleanup: BuildTubes' simple cut lets some tubes run past their node
'     (centroid shifts up to 42 mm along the tube). Where such an overrun goes
'     through the boundary tube, the coped trim leaves the overrun on the far
'     side as its own small body. After the trims, every body that is not the
'     largest body of its nearest tube, is at most 20 cm3 and a quarter of that
'     tube, and sits within 60 mm of one of the tube's end nodes is removed
'     with one Delete/Keep Body feature (StubsDeleted_<n>). Anything else that
'     is extra is listed and left alone.
'   * A re-run on a part whose rows are all done still runs the cleanup, so the
'     saved chassis can be repaired without a rebuild.
'   * The body check is: bodies after = tubes in frame_tubes.csv (114).
'
' Depends on run-time behaviour (not provable from the type library)
'   * The EndCond argument: swSolidworksWeldmentEndCondOptions_e.swEndConditionTrim
'     (4) is the weldment "end trim" value in the 2026 constants; the API
'     help that names the enum for this argument could not be read.
'   * Options swWeldmentTrimExtendOption_CopedCut (4) for round tubes.
'   * Which side of a trimmed body is kept: SolidWorks keeps the longer part,
'     which is the tube (the cut-off piece is inside the boundary tube).
'   * The boundary tube's own end at a node stays where BuildTubes left it
'     (flat at the node centre, inside the joint); only the other tubes are cut.
'   * Late-bound: GetBodies2, Body2.GetMassProperties, the
'     cut-list sub-feature walk, CustomPropertyManager LENGTH.
' ============================================================================
Option Explicit

Private Const TRIM_VERSION As String = "TrimTubes v4, 2026-11-17: match = distance from body centroid to tube centreline segment, radius 12 mm, tie margin 8 mm; done rows recorded as custom properties TrimDone_<node>; body count after every trim; stub cleanup"
Private Const MATCH_MM As Double = 12#     ' centroid to own centreline (real: 0.3 to 4.1 mm)
Private Const STUB_MAX_MM3 As Double = 20000#   ' a stub is at most 20 cm3 (an 80 mm overrun of a 25.4x2.4 tube is 13.8 cm3)
Private Const STUB_MAX_FRACTION As Double = 0.25 ' and at most a quarter of its tube's volume
Private Const STUB_NODE_MM As Double = 60#     ' and its centroid within 60 mm of one end node of the tube
Private Const TIE_MM As Double = 8#        ' next tube must be this much further (real: 54 mm or more)

Sub main()
    Dim swApp As SldWorks.SldWorks
    Dim swModel As SldWorks.ModelDoc2
    Dim swPart As SldWorks.PartDoc
    Dim swFeatMgr As SldWorks.FeatureManager
    Set swApp = Application.SldWorks
    Set swModel = swApp.ActiveDoc
    If swModel Is Nothing Then
        MsgBox "Open cad\chassis\chassis.SLDPRT (after BuildTubes) first. Nothing was changed.", vbExclamation
        Exit Sub
    End If
    If swModel.GetType <> swDocPART Then
        MsgBox "The active document must be a part. Nothing was changed.", vbExclamation
        Exit Sub
    End If
    If swModel.GetPathName = "" Then
        MsgBox "Save the part first (BuildTubes saves it as cad\chassis\chassis.SLDPRT). Nothing was changed.", vbExclamation
        Exit Sub
    End If
    Set swPart = swModel
    Set swFeatMgr = swModel.FeatureManager

    Dim repoRoot As String, nodesFile As String, tubesFile As String, planFile As String, reportFile As String
    repoRoot = RepoRootFromMacroPath()
    nodesFile = repoRoot & "\cad\frame\frame_nodes.csv"
    tubesFile = repoRoot & "\cad\frame\frame_tubes.csv"
    planFile = repoRoot & "\cad\frame\frame_trims.csv"
    reportFile = repoRoot & "\cad\chassis\trim_tubes_report.txt"
    If Dir(nodesFile) = "" Or Dir(tubesFile) = "" Or Dir(planFile) = "" Then
        MsgBox "Missing " & IIf(Dir(planFile) = "", planFile & " (run frame_trims in MATLAB)", nodesFile & " or " & tubesFile) & _
               ". Nothing was changed.", vbExclamation
        Exit Sub
    End If

    ' --- tubes: id -> Array(ax, ay, az, bx, by, bz), the centreline end points in mm ---
    Dim nodes As Object, tubes As Object
    Set nodes = CreateObject("Scripting.Dictionary")
    Set tubes = CreateObject("Scripting.Dictionary")
    Dim tubeVol As Object
    Set tubeVol = CreateObject("Scripting.Dictionary")
    Dim lines As Variant, k As Long, ln As String, parts() As String
    lines = ReadTextLines(nodesFile)
    For k = 1 To UBound(lines)
        ln = Trim$(lines(k))
        If ln <> "" And Left$(ln, 1) <> "#" Then
            parts = Split(ln, ",")
            If UBound(parts) >= 3 Then nodes(Trim$(parts(0))) = Array(Val(parts(1)), Val(parts(2)), Val(parts(3)))
        End If
    Next k
    Dim a As Variant, b As Variant
    lines = ReadTextLines(tubesFile)
    For k = 1 To UBound(lines)
        ln = Trim$(lines(k))
        If ln <> "" And Left$(ln, 1) <> "#" Then
            parts = Split(ln, ",")
            If UBound(parts) >= 4 Then
                If nodes.Exists(Trim$(parts(1))) And nodes.Exists(Trim$(parts(2))) Then
                    a = nodes(Trim$(parts(1))): b = nodes(Trim$(parts(2)))
                    tubes(Trim$(parts(0))) = Array(a(0), a(1), a(2), b(0), b(1), b(2))
                    If UBound(parts) >= 5 Then tubeVol(Trim$(parts(0))) = 3.14159265 / 4# * (Val(parts(4)) ^ 2 - (Val(parts(4)) - 2 * Val(parts(5))) ^ 2) * _
                        Sqr((b(0) - a(0)) ^ 2 + (b(1) - a(1)) ^ 2 + (b(2) - a(2)) ^ 2)
                End If
            End If
        End If
    Next k

    ' --- plan rows ------------------------------------------------------------------
    Dim planLines As Variant, nRows As Long
    planLines = ReadTextLines(planFile)
    Dim rowName() As String, rowNode() As String, rowB() As String, rowT() As String, rowState() As String
    ReDim rowName(1 To UBound(planLines) + 1): ReDim rowNode(1 To UBound(planLines) + 1)
    ReDim rowB(1 To UBound(planLines) + 1): ReDim rowT(1 To UBound(planLines) + 1): ReDim rowState(1 To UBound(planLines) + 1)
    For k = 1 To UBound(planLines)
        ln = Trim$(planLines(k))
        If ln <> "" And Left$(ln, 1) <> "#" Then
            parts = Split(ln, ",")
            If UBound(parts) >= 3 Then
                nRows = nRows + 1
                rowName(nRows) = Trim$(parts(0)): rowNode(nRows) = Trim$(parts(1))
                rowB(nRows) = Trim$(parts(2)): rowT(nRows) = Trim$(parts(3))
            End If
        End If
    Next k
    If nRows = 0 Then
        MsgBox "No rows in " & planFile & ". Nothing was changed.", vbExclamation
        Exit Sub
    End If

    ' --- 1. checks: bodies and matching, nothing changed --------------------------------
    ' Diagnostics first (nothing changed): feature tree, trim features, done records,
    ' and the full tube <-> body distance table from the part as it is now.
    Dim cpm As SldWorks.CustomPropertyManager
    Set cpm = swModel.Extension.CustomPropertyManager("")
    Dim treeTxt As String, trimList As String, nTrimAll As Long
    treeTxt = FeatureTree(swModel, trimList, nTrimAll)
    Dim diagTxt As String
    diagTxt = MatchTable(swPart, tubes)
    Dim rowDone() As String, nDoneRows As Long, r0 As Long, rec As String
    ReDim rowDone(1 To nRows)
    For r0 = 1 To nRows
        rec = DoneRecord(cpm, rowNode(r0))
        If Not FindFeatureDeep(swModel, rowName(r0)) Is Nothing Then
            rowDone(r0) = "by name"
        ElseIf rec <> "" Then
            rowDone(r0) = "by record TrimDone_" & rowNode(r0) & " = " & rec
        End If
        If rowDone(r0) <> "" Then nDoneRows = nDoneRows + 1
    Next r0
    Dim header As String
    header = TRIM_VERSION & vbCrLf & "Part: " & swModel.GetPathName & vbCrLf & _
             "Trim features in the part before this run: " & nTrimAll & "; plan rows already done (by name or record): " & nDoneRows & vbCrLf
    ' Re-run guard: more trim features than rows known to be done means some rows were
    ' trimmed under a name and without a record this macro can see. Stop, do not trim twice.
    If nTrimAll > nDoneRows Then
        WriteReport reportFile, "STOPPED, NOTHING CHANGED   (" & Format(Now, "yyyy-mm-dd hh:nn") & ")" & vbCrLf & header & vbCrLf & _
            "The part has " & nTrimAll & " trim features but only " & nDoneRows & " plan rows are known to be done, so " & _
            (nTrimAll - nDoneRows) & " trim features cannot be tied to a row. Running would trim those tube ends again." & vbCrLf & vbCrLf & _
            "Trim features:" & vbCrLf & trimList & vbCrLf & "Feature tree (top level):" & vbCrLf & treeTxt & vbCrLf & diagTxt
        MsgBox TRIM_VERSION & vbCrLf & vbCrLf & "STOPPED: " & nTrimAll & " trim features in the part, but only " & nDoneRows & _
               " plan rows are known to be done. Nothing was changed." & vbCrLf & vbCrLf & _
               "Report with every trim feature and the tube/body table: " & reportFile, vbExclamation
        Exit Sub
    End If
    Dim bodyOf As Object, unmatched As String, nBodies0 As Long
    Set bodyOf = MatchBodies(swPart, tubes, unmatched, nBodies0)
    Dim r As Long, ids As Variant, j As Long, nToDo As Long, nKept As Long, why As String
    For r = 1 To nRows
        If rowDone(r) <> "" Then
            rowState(r) = "kept " & rowDone(r)
            nKept = nKept + 1
            GoTo NextRowCheck
        End If
        why = ""
        ids = Split(rowB(r) & ";" & rowT(r), ";")
        For j = 0 To UBound(ids)
            If Not tubes.Exists(ids(j)) Then
                why = why & ids(j) & " not in frame_tubes.csv; "
            ElseIf Not bodyOf.Exists(ids(j)) Then
                why = why & ids(j) & " has no matching body; "
            End If
        Next j
        If why = "" Then
            rowState(r) = "todo"
            nToDo = nToDo + 1
        Else
            rowState(r) = "skip: " & why
        End If
NextRowCheck:
    Next r
    If nToDo = 0 Then
        Dim pre As String
        For r = 1 To nRows
            If Left$(rowState(r), 4) = "skip" Then pre = pre & "  " & rowName(r) & ": " & Mid$(rowState(r), 7) & vbCrLf
        Next r
        Dim stubs0 As Collection, stubTxt0 As String
        Set stubs0 = New Collection
        stubTxt0 = FindStubs(swPart, tubes, tubeVol, stubs0)
        If pre = "" And stubs0.Count > 0 Then
            ' all rows done, but stubs to clean: carry on to the cleanup below
        ElseIf pre = "" Then
            WriteReport reportFile, "NOTHING CHANGED (" & Format(Now, "yyyy-mm-dd hh:nn") & "): all " & nKept & " plan rows done, no stubs" & vbCrLf & _
                        header & vbCrLf & stubTxt0 & vbCrLf & "Trim features:" & vbCrLf & trimList & vbCrLf & diagTxt
            MsgBox TRIM_VERSION & vbCrLf & vbCrLf & "All " & nKept & " plan rows are already done and there are no stubs. Nothing was changed." & _
                   vbCrLf & "Report: " & reportFile, vbInformation
            Exit Sub
        Else
            WriteReport reportFile, "NOTHING CHANGED (" & Format(Now, "yyyy-mm-dd hh:nn") & ")" & vbCrLf & vbCrLf & _
                        "Bodies: " & nBodies0 & ", tubes in CSV: " & tubes.Count & vbCrLf & "Unmatched: " & unmatched & vbCrLf & vbCrLf & pre & _
                        vbCrLf & header & vbCrLf & "Trim features:" & vbCrLf & trimList & vbCrLf & diagTxt
            MsgBox TRIM_VERSION & vbCrLf & vbCrLf & "No trim row can be made. Nothing was changed." & vbCrLf & "Report: " & reportFile, vbExclamation
            Exit Sub
        End If
    End If

    ' mass before
    Dim mp As SldWorks.MassProperty, mass0 As Double, mass1 As Double
    Set mp = swModel.Extension.CreateMassProperty
    If Not mp Is Nothing Then mass0 = mp.Mass

    ' --- 2. trims -------------------------------------------------------------------------
    Dim report As String, failures As String, allPass As Boolean, nDone As Long
    Dim bArr() As Object, tArr() As Object, nb As Long, nt As Long, bIds As Variant, tIds As Variant
    Dim trimType As String, namesBefore As Object, nAfter As Long, splitTxt As String, newNames As String
    Dim f As SldWorks.Feature, modeTxt As String, err1 As String, dummy As String, dummyN As Long
    allPass = True
    For r = 1 To nRows
        If Left$(rowState(r), 4) = "kept" Then
            report = report & "PASS  " & rowName(r) & ": already done (" & Mid$(rowState(r), 6) & "), kept" & vbCrLf
            GoTo NextRow
        End If
        If Left$(rowState(r), 4) = "skip" Then
            report = report & "FAIL  " & rowName(r) & ": not made, " & Mid$(rowState(r), 7) & vbCrLf
            failures = failures & "- " & rowName(r) & ": " & Mid$(rowState(r), 7) & vbCrLf
            allPass = False
            GoTo NextRow
        End If
        ' bodies change with every trim: match again
        Set bodyOf = MatchBodies(swPart, tubes, dummy, dummyN)
        Set namesBefore = BodyNames(swPart)
        bIds = Split(rowB(r), ";"): tIds = Split(rowT(r), ";")
        ReDim bArr(0 To UBound(bIds)): ReDim tArr(0 To UBound(tIds))
        nb = 0: nt = 0: why = ""
        For j = 0 To UBound(bIds)
            If bodyOf.Exists(bIds(j)) Then Set bArr(nb) = bodyOf(bIds(j)): nb = nb + 1 Else why = why & bIds(j) & " "
        Next j
        For j = 0 To UBound(tIds)
            If bodyOf.Exists(tIds(j)) Then Set tArr(nt) = bodyOf(tIds(j)): nt = nt + 1 Else why = why & tIds(j) & " "
        Next j
        If why <> "" Then
            report = report & "FAIL  " & rowName(r) & ": lost the match for " & why & "after earlier trims" & vbCrLf
            failures = failures & "- " & rowName(r) & ": no body for " & why & vbCrLf
            allPass = False
            GoTo NextRow
        End If
        swModel.ClearSelection2 True
        Set f = TrimFeature(swFeatMgr, tArr, bArr, swWeldmentTrimExtendOptionType_e.swWeldmentTrimExtendOption_CopedCut)
        modeTxt = "coped"
        If f Is Nothing Then
            err1 = CreateErrors(swFeatMgr)
            swModel.ClearSelection2 True
            Set f = TrimFeature(swFeatMgr, tArr, bArr, 0)
            modeTxt = "planar (coped refused: " & err1 & ")"
        End If
        If f Is Nothing Then
            report = report & "FAIL  " & rowName(r) & ": refused (" & CreateErrors(swFeatMgr) & ")" & vbCrLf
            failures = failures & "- " & rowName(r) & " at node " & rowNode(r) & ": boundary " & rowB(r) & ", trimmed " & rowT(r) & _
                       ": SolidWorks says " & CreateErrors(swFeatMgr) & " (coped: " & err1 & ")" & vbCrLf
            allPass = False
            GoTo NextRow
        End If
        On Error Resume Next
        f.Name = rowName(r)
        On Error GoTo 0
        If f.Name <> rowName(r) Then modeTxt = modeTxt & ", NOT renamed (is " & f.Name & ")"
        nDone = nDone + 1
        If trimType = "" Then trimType = f.GetTypeName2
        ' record the row as done, independent of the feature name
        If Not cpm Is Nothing Then
            cpm.Add3 "TrimDone_" & rowNode(r), swCustomInfoType_e.swCustomInfoText, f.Name, _
                     swCustomPropertyAddOption_e.swCustomPropertyReplaceValue
        End If
        report = report & "PASS  " & rowName(r) & ": " & nt & " ends against " & nb & " boundary tube(s), " & modeTxt & vbCrLf
        nAfter = BodyCount(swPart)
        If nAfter <> namesBefore.Count Then
            newNames = NewBodyNames(swPart, namesBefore)
            splitTxt = splitTxt & "- " & rowName(r) & ": bodies " & namesBefore.Count & " -> " & nAfter & "; trimmed " & rowT(r) & _
                       " against " & rowB(r) & "; bodies with a new name after it: " & newNames & vbCrLf
            report = report & "SPLIT " & rowName(r) & ": bodies " & namesBefore.Count & " -> " & nAfter & " (new body names: " & newNames & ")" & vbCrLf
        End If
NextRow:
    Next r
    swModel.ClearSelection2 True
    swModel.ForceRebuild3 False

    ' --- 2b. stub cleanup -------------------------------------------------------------------
    Dim stubs As Collection, stubTxt As String, nDel As Long, delName As String
    Set stubs = New Collection
    stubTxt = FindStubs(swPart, tubes, tubeVol, stubs)
    If stubs.Count > 0 Then
        delName = DeleteStubs(swModel, swFeatMgr, stubs, cpm)
        If delName = "" Then
            report = report & "FAIL  stub cleanup: Delete/Keep Body refused (" & CreateErrors(swFeatMgr) & ")" & vbCrLf
            failures = failures & "- stub cleanup refused: " & stubs.Count & " stubs stay" & vbCrLf
            allPass = False
        Else
            nDel = stubs.Count
            report = report & "PASS  " & delName & ": " & nDel & " stub bodies deleted" & vbCrLf
        End If
        swModel.ForceRebuild3 False
    End If

    ' --- 3. totals -------------------------------------------------------------------------
    Dim nBodies1 As Long, cutLen_m As Double, lenMissing As Long, nFolders As Long, nCut As Long
    UpdateCutList swModel, nCut, cutLen_m, lenMissing, nFolders
    Dim bodies As Variant
    bodies = swPart.GetBodies2(swBodyType_e.swSolidBody, False)
    If Not IsEmpty(bodies) Then nBodies1 = UBound(bodies) + 1
    Set mp = swModel.Extension.CreateMassProperty
    If Not mp Is Nothing Then mass1 = mp.Mass

    Dim summary As String
    summary = report & vbCrLf
    summary = summary & PassFail(nBodies1 = tubes.Count, allPass) & "  bodies: " & nBodies0 & " before, " & nBodies1 & " after, " & tubes.Count & _
              " tubes in frame_tubes.csv (must be equal after the run)" & vbCrLf
    summary = summary & PassFail(mass1 <= mass0 And mass1 >= 38 And mass1 <= 46, allPass) & "  mass: " & Format(mass0, "0.00") & " kg before, " & _
              Format(mass1, "0.00") & " kg after (" & Format(mass1 - mass0, "+0.00;-0.00") & " kg; must not rise, 38 to 46)" & vbCrLf
    If lenMissing > 0 Or nFolders = 0 Then
        summary = summary & "INFO  cut length: LENGTH missing on " & lenMissing & " of " & nFolders & " cut-list items" & vbCrLf
    Else
        summary = summary & "INFO  cut length after trim: " & Format(cutLen_m, "0.00") & " m (" & nCut & " bodies in the cut list)" & vbCrLf
    End If

    ' --- 4. save ---------------------------------------------------------------------------
    Dim saved As Boolean, errs As Long, warns As Long
    If nDone > 0 Or nDel > 0 Then
        saved = swModel.Save3(swSaveAsOptions_e.swSaveAsOptions_Silent, errs, warns)
        summary = summary & PassFail(saved, allPass) & "  saved: " & IIf(saved, swModel.GetPathName, "NOT saved (error " & errs & ")") & vbCrLf
    Else
        summary = summary & "INFO  nothing changed, not saved" & vbCrLf
    End If

    Dim full As String
    full = IIf(allPass, "ALL PASS", "SOME CHECKS FAILED") & "   (" & Format(Now, "yyyy-mm-dd hh:nn") & ", " & nDone & " trims made, " & _
           nKept & " kept, " & nDel & " stubs deleted, " & nRows & " in plan)" & vbCrLf & header & _
           "made = new trim features inserted in this run; kept = rows already done before it (by name Trim_<node> or record TrimDone_<node>)" & _
           vbCrLf & vbCrLf & summary & vbCrLf & _
           IIf(failures = "", "No failures.", "Failures:" & vbCrLf & failures) & _
           vbCrLf & vbCrLf & "Trims that changed the body count:" & vbCrLf & IIf(splitTxt = "", "  (none in this run)" & vbCrLf, splitTxt) & _
           vbCrLf & "Stubs found after the trims:" & vbCrLf & stubTxt & _
           IIf(unmatched = "", "", vbCrLf & "Bodies or tubes without a match before trimming: " & unmatched) & _
           IIf(trimType = "", "", vbCrLf & "Type name of the trim features made in this run: " & trimType) & vbCrLf & vbCrLf & _
           "Trim features before this run:" & vbCrLf & trimList & vbCrLf & "BEFORE this run:" & vbCrLf & diagTxt & vbCrLf & _
           "AFTER this run:" & vbCrLf & MatchTable(swPart, tubes)
    WriteReport reportFile, full
    Debug.Print full
    Dim shortTxt As String
    shortTxt = TRIM_VERSION & vbCrLf & vbCrLf & IIf(allPass, "ALL PASS", "SOME CHECKS FAILED") & ": " & nDone & " trims made, " & nKept & " kept, " & nDel & " stubs deleted, " & nRows & " in plan." & vbCrLf & vbCrLf & _
               Mid$(summary, Len(report) + 3)
    If splitTxt <> "" Then shortTxt = shortTxt & vbCrLf & "Trims that changed the body count:" & vbCrLf & Left$(splitTxt, 400)
    If failures <> "" Then shortTxt = shortTxt & vbCrLf & "Failures:" & vbCrLf & Left$(failures, 500)
    MsgBox shortTxt & vbCrLf & vbCrLf & "Full report: " & reportFile, IIf(allPass, vbInformation, vbExclamation)
End Sub

Private Function TrimFeature(ByVal swFeatMgr As SldWorks.FeatureManager, ByRef tArr() As Object, ByRef bArr() As Object, _
                             ByVal opts As Long) As SldWorks.Feature
    Dim tVar As Variant, bVar As Variant
    tVar = tArr: bVar = bArr
    Set TrimFeature = swFeatMgr.InsertWeldmentTrimFeature2(swSolidworksWeldmentEndCondOptions_e.swEndConditionTrim, _
                                                          opts, 0#, tVar, bVar)
End Function

' Match every solid body to one tube id: its centroid is within MATCH_MM of the
' tube's centreline segment and the next tube is TIE_MM further. Returns
' tube id -> Body2. Lists what is left.
Private Function MatchBodies(ByVal swPart As SldWorks.PartDoc, ByVal tubes As Object, ByRef unmatched As String, _
                             ByRef nBodies As Long) As Object
    Dim res As Object, used As Object
    Set res = CreateObject("Scripting.Dictionary")
    Set used = CreateObject("Scripting.Dictionary")
    unmatched = ""
    Dim bodies As Variant, k As Long, mpv As Variant, key As Variant, t As Variant, secondId As String
    Dim best As Double, second As Double, bestId As String, s As Double
    bodies = swPart.GetBodies2(swBodyType_e.swSolidBody, False)
    nBodies = 0
    If IsEmpty(bodies) Then
        unmatched = "no solid bodies"
        Set MatchBodies = res
        Exit Function
    End If
    nBodies = UBound(bodies) + 1
    Dim swBody As SldWorks.Body2
    For k = 0 To UBound(bodies)
        Set swBody = bodies(k)
        mpv = swBody.GetMassProperties(7900#)
        best = 1E+30: second = 1E+30: bestId = "": secondId = ""
        For Each key In tubes.Keys
            t = tubes(key)
            s = DistToSegment(mpv(0) * 1000, mpv(1) * 1000, mpv(2) * 1000, t)
            If s < best Then
                second = best: secondId = bestId: best = s: bestId = CStr(key)
            ElseIf s < second Then
                second = s: secondId = CStr(key)
            End If
        Next key
        If bestId <> "" And best <= MATCH_MM And second - best >= TIE_MM And Not used.Exists(bestId) Then
            Set res(bestId) = swBody
            used(bestId) = True
        Else
            unmatched = unmatched & "body " & k & " at (" & Format(mpv(0) * 1000, "0") & "," & Format(mpv(1) * 1000, "0") & "," & _
                        Format(mpv(2) * 1000, "0") & ") mm, best " & bestId & " " & Format(best, "0.0") & " mm, next " & _
                        secondId & " " & Format(second, "0.0") & " mm" & IIf(used.Exists(bestId), " (already taken)", "") & "; "
        End If
    Next k
    For Each key In tubes.Keys
        If Not res.Exists(key) Then unmatched = unmatched & "tube " & key & " has no body; "
    Next key
    Set MatchBodies = res
End Function

' Distance (mm) from point (x, y, z) to the segment t = Array(ax, ay, az, bx, by, bz).
Private Function DistToSegment(ByVal x As Double, ByVal y As Double, ByVal z As Double, ByVal t As Variant) As Double
    Dim vx As Double, vy As Double, vz As Double, L2 As Double, u As Double
    vx = t(3) - t(0): vy = t(4) - t(1): vz = t(5) - t(2)
    L2 = vx * vx + vy * vy + vz * vz
    If L2 > 0 Then u = ((x - t(0)) * vx + (y - t(1)) * vy + (z - t(2)) * vz) / L2
    If u < 0 Then u = 0
    If u > 1 Then u = 1
    DistToSegment = Dist3(x, y, z, t(0) + u * vx, t(1) + u * vy, t(2) + u * vz)
End Function

Private Function Dist3(ByVal x1 As Double, ByVal y1 As Double, ByVal z1 As Double, _
                       ByVal x2 As Double, ByVal y2 As Double, ByVal z2 As Double) As Double
    Dist3 = Sqr((x1 - x2) ^ 2 + (y1 - y2) ^ 2 + (z1 - z2) ^ 2)
End Function

' Update the cut list and total it: bodies, and sum of LENGTH (mm) x bodies per item.
Private Sub UpdateCutList(ByVal swModel As SldWorks.ModelDoc2, ByRef nBodies As Long, ByRef cutLen_m As Double, _
                          ByRef lenMissing As Long, ByRef nFolders As Long)
    Dim f As SldWorks.Feature, sf As SldWorks.Feature
    Dim swFolder As SldWorks.BodyFolder, cpm As SldWorks.CustomPropertyManager
    Dim valOut As String, resOut As String, wasRes As Boolean, linked As Boolean, cnt As Long
    Set f = swModel.FirstFeature
    Do While Not f Is Nothing
        If f.GetTypeName2 = "SolidBodyFolder" Then
            Set swFolder = f.GetSpecificFeature2
            If Not swFolder Is Nothing Then
                swFolder.SetAutomaticUpdate True
                swFolder.UpdateCutList
            End If
        End If
        Set f = f.GetNextFeature
    Loop
    swModel.ForceRebuild3 False
    Set f = swModel.FirstFeature
    Do While Not f Is Nothing
        If f.GetTypeName2 = "SolidBodyFolder" Then
            Set sf = f.GetFirstSubFeature
            Do While Not sf Is Nothing
                If sf.GetTypeName2 = "CutListFolder" Then
                    Set swFolder = sf.GetSpecificFeature2
                    cnt = 0
                    If Not swFolder Is Nothing Then cnt = swFolder.GetBodyCount
                    If cnt > 0 Then
                        nFolders = nFolders + 1
                        nBodies = nBodies + cnt
                        Set cpm = sf.CustomPropertyManager
                        valOut = "": resOut = ""
                        If Not cpm Is Nothing Then cpm.Get6 "LENGTH", False, valOut, resOut, wasRes, linked
                        If resOut <> "" And IsNumeric(resOut) Then
                            cutLen_m = cutLen_m + Val(resOut) / 1000# * cnt
                        Else
                            lenMissing = lenMissing + 1
                        End If
                    End If
                End If
                Set sf = sf.GetNextSubFeature
            Loop
        End If
        Set f = f.GetNextFeature
    Loop
End Sub

Private Sub WriteReport(ByVal path As String, ByVal txt As String)
    Dim fnum As Integer, folder As String
    folder = Left$(path, InStrRev(path, "\") - 1)
    If Dir(folder, vbDirectory) = "" Then MkDir folder
    fnum = FreeFile
    Open path For Output As #fnum
    Print #fnum, txt
    Close #fnum
End Sub

Private Function PassFail(ByVal ok As Boolean, ByRef allPass As Boolean) As String
    If ok Then
        PassFail = "PASS"
    Else
        PassFail = "FAIL"
        allPass = False
    End If
End Function

' Text of the last feature-creation errors, or "(no message)".
Private Function CreateErrors(ByVal swFeatMgr As SldWorks.FeatureManager) As String
    Dim msgs As Variant, featType As String, n As Long, k As Long, s As String
    n = swFeatMgr.GetCreateFeatureErrors(msgs, featType)
    If n > 0 And IsArray(msgs) Then
        For k = 0 To UBound(msgs)
            s = s & msgs(k) & "; "
        Next k
    End If
    If s = "" Then s = "(no message)"
    CreateErrors = s
End Function

' Top-level feature tree as text; collects every trim feature (name Trim_*,
' default name Trim/Extend<n>, or a type name containing "Trim"), sub-features too.
Private Function FeatureTree(ByVal swModel As SldWorks.ModelDoc2, ByRef trimList As String, ByRef nTrim As Long) As String
    Dim f As SldWorks.Feature, sf As SldWorks.Feature, k As Long, txt As String
    Set f = swModel.FirstFeature
    Do While Not f Is Nothing
        k = k + 1
        txt = txt & "  " & Format(k, "000") & "  " & f.Name & "  [" & f.GetTypeName2 & "]" & vbCrLf
        If IsTrimFeature(f) Then
            nTrim = nTrim + 1
            trimList = trimList & "  " & f.Name & "  [" & f.GetTypeName2 & "]" & vbCrLf
        End If
        Set sf = f.GetFirstSubFeature
        Do While Not sf Is Nothing
            If IsTrimFeature(sf) Then
                nTrim = nTrim + 1
                trimList = trimList & "  " & sf.Name & "  [" & sf.GetTypeName2 & "]  (sub-feature of " & f.Name & ")" & vbCrLf
            End If
            Set sf = sf.GetNextSubFeature
        Loop
        Set f = f.GetNextFeature
    Loop
    If trimList = "" Then trimList = "  (none)" & vbCrLf
    FeatureTree = txt
End Function

Private Function IsTrimFeature(ByVal f As SldWorks.Feature) As Boolean
    Dim nm As String
    nm = LCase$(f.Name)
    IsTrimFeature = (Left$(nm, 5) = "trim_") Or (Left$(nm, 11) = "trim/extend") Or _
                    (InStr(1, f.GetTypeName2, "Trim", vbTextCompare) > 0)
End Function

' Value of the custom property TrimDone_<node> (the trim feature's name when it was made), or "".
Private Function DoneRecord(ByVal cpm As SldWorks.CustomPropertyManager, ByVal node As String) As String
    Dim v As String, res As String, wasRes As Boolean, linked As Boolean
    If cpm Is Nothing Then Exit Function
    cpm.Get6 "TrimDone_" & node, False, v, res, wasRes, linked
    DoneRecord = res
End Function

' Tube <-> body distance table from the part as it is (nothing changed). Distances in mm
' from each body's centroid to each tube's centreline segment.
Private Function MatchTable(ByVal swPart As SldWorks.PartDoc, ByVal tubes As Object) As String
    Dim bodies As Variant, nB As Long, k As Long, i As Long, mpv As Variant, swBody As SldWorks.Body2
    bodies = swPart.GetBodies2(swBodyType_e.swSolidBody, False)
    If IsEmpty(bodies) Then
        MatchTable = "No solid bodies." & vbCrLf
        Exit Function
    End If
    nB = UBound(bodies) + 1
    Dim cx() As Double, cy() As Double, cz() As Double, bn() As String
    ReDim cx(nB - 1): ReDim cy(nB - 1): ReDim cz(nB - 1): ReDim bn(nB - 1)
    For k = 0 To nB - 1
        Set swBody = bodies(k)
        mpv = swBody.GetMassProperties(7900#)
        cx(k) = mpv(0) * 1000: cy(k) = mpv(1) * 1000: cz(k) = mpv(2) * 1000
        bn(k) = swBody.Name
    Next k
    Dim keys As Variant, nT As Long, d() As Double
    keys = tubes.keys
    nT = tubes.Count
    ReDim d(nT - 1, nB - 1)
    For i = 0 To nT - 1
        For k = 0 To nB - 1
            d(i, k) = DistToSegment(cx(k), cy(k), cz(k), tubes(keys(i)))
        Next k
    Next i
    Dim txt As String, t As Variant, b1 As Long, b2 As Long, t1 As Long, t2 As Long, ok As Boolean, nBad As Long, nextTxt As String
    txt = "Tube table (mm). tube | centreline A -> B | nearest body: index, name, centroid, distance to segment | next body: index, distance | " & _
          "OK if nearest <= " & Format(MATCH_MM, "0") & " and next >= nearest + " & Format(TIE_MM, "0") & vbCrLf
    For i = 0 To nT - 1
        t = tubes(keys(i))
        b1 = -1: b2 = -1
        For k = 0 To nB - 1
            If b1 < 0 Then
                b1 = k
            ElseIf d(i, k) < d(i, b1) Then
                b2 = b1: b1 = k
            ElseIf b2 < 0 Then
                b2 = k
            ElseIf d(i, k) < d(i, b2) Then
                b2 = k
            End If
        Next k
        ok = d(i, b1) <= MATCH_MM
        nextTxt = ""
        If b2 >= 0 Then
            ok = ok And (d(i, b2) - d(i, b1) >= TIE_MM)
            nextTxt = " | body " & b2 & " " & Format(d(i, b2), "0.0")
        End If
        txt = txt & "  " & keys(i) & " | (" & Format(t(0), "0") & "," & Format(t(1), "0") & "," & Format(t(2), "0") & ") -> (" & _
              Format(t(3), "0") & "," & Format(t(4), "0") & "," & Format(t(5), "0") & ") | body " & b1 & " " & bn(b1) & " (" & _
              Format(cx(b1), "0.0") & "," & Format(cy(b1), "0.0") & "," & Format(cz(b1), "0.0") & ") " & Format(d(i, b1), "0.0") & _
              nextTxt & " | " & IIf(ok, "OK", "NO MATCH") & vbCrLf
    Next i
    txt = txt & vbCrLf & "Bodies matched to no tube (mm): index, name, centroid | nearest tube, distance | next tube, distance" & vbCrLf
    For k = 0 To nB - 1
        t1 = -1: t2 = -1
        For i = 0 To nT - 1
            If t1 < 0 Then
                t1 = i
            ElseIf d(i, k) < d(t1, k) Then
                t2 = t1: t1 = i
            ElseIf t2 < 0 Then
                t2 = i
            ElseIf d(i, k) < d(t2, k) Then
                t2 = i
            End If
        Next i
        ok = d(t1, k) <= MATCH_MM
        nextTxt = ""
        If t2 >= 0 Then
            ok = ok And (d(t2, k) - d(t1, k) >= TIE_MM)
            nextTxt = " | " & keys(t2) & " " & Format(d(t2, k), "0.0")
        End If
        If Not ok Then
            nBad = nBad + 1
            txt = txt & "  body " & k & " " & bn(k) & " (" & Format(cx(k), "0.0") & "," & Format(cy(k), "0.0") & "," & _
                  Format(cz(k), "0.0") & ") | " & keys(t1) & " " & Format(d(t1, k), "0.0") & nextTxt & vbCrLf
        End If
    Next k
    If nBad = 0 Then txt = txt & "  (none: every body matches one tube)" & vbCrLf
    MatchTable = txt
End Function

Private Function BodyCount(ByVal swPart As SldWorks.PartDoc) As Long
    Dim bodies As Variant
    bodies = swPart.GetBodies2(swBodyType_e.swSolidBody, False)
    If Not IsEmpty(bodies) Then BodyCount = UBound(bodies) + 1
End Function

' Body name -> True for every solid body.
Private Function BodyNames(ByVal swPart As SldWorks.PartDoc) As Object
    Dim d As Object, bodies As Variant, k As Long, swBody As SldWorks.Body2
    Set d = CreateObject("Scripting.Dictionary")
    bodies = swPart.GetBodies2(swBodyType_e.swSolidBody, False)
    If Not IsEmpty(bodies) Then
        For k = 0 To UBound(bodies)
            Set swBody = bodies(k)
            d(swBody.Name & "#" & k) = True
        Next k
    End If
    Set BodyNames = d
End Function

' Names (with centroid) of bodies whose name was not there before.
Private Function NewBodyNames(ByVal swPart As SldWorks.PartDoc, ByVal before As Object) As String
    Dim old As Object, key As Variant, bodies As Variant, k As Long, swBody As SldWorks.Body2, mpv As Variant, s As String
    Set old = CreateObject("Scripting.Dictionary")
    For Each key In before.Keys
        old(Left$(key, InStrRev(key, "#") - 1)) = True
    Next key
    bodies = swPart.GetBodies2(swBodyType_e.swSolidBody, False)
    If IsEmpty(bodies) Then Exit Function
    For k = 0 To UBound(bodies)
        Set swBody = bodies(k)
        If Not old.Exists(swBody.Name) Then
            mpv = swBody.GetMassProperties(7900#)
            s = s & swBody.Name & " at (" & Format(mpv(0) * 1000, "0") & "," & Format(mpv(1) * 1000, "0") & "," & _
                Format(mpv(2) * 1000, "0") & ") mm, " & Format(mpv(3) * 1000000000#, "0") & " mm3; "
        End If
    Next k
    If s = "" Then s = "(no new names; compare the AFTER table)"
    NewBodyNames = s
End Function

' Stubs: bodies that are not the largest body of their nearest tube, are small
' (<= STUB_MAX_MM3 and <= STUB_MAX_FRACTION of the tube) and sit within
' STUB_NODE_MM of one end node of that tube. Fills stubs; returns a text list
' that also names every other extra body (left alone).
Private Function FindStubs(ByVal swPart As SldWorks.PartDoc, ByVal tubes As Object, ByVal tubeVol As Object, _
                           ByRef stubs As Collection) As String
    Dim bodies As Variant, nB As Long, k As Long, i As Long, swBody As SldWorks.Body2, mpv As Variant
    bodies = swPart.GetBodies2(swBodyType_e.swSolidBody, False)
    If IsEmpty(bodies) Then
        FindStubs = "  (no bodies)" & vbCrLf
        Exit Function
    End If
    nB = UBound(bodies) + 1
    Dim keys As Variant, nearest() As String, vol() As Double, cx() As Double, cy() As Double, cz() As Double, dist() As Double
    ReDim nearest(nB - 1): ReDim vol(nB - 1): ReDim cx(nB - 1): ReDim cy(nB - 1): ReDim cz(nB - 1): ReDim dist(nB - 1)
    keys = tubes.Keys
    Dim d As Double, best As Double
    For k = 0 To nB - 1
        Set swBody = bodies(k)
        mpv = swBody.GetMassProperties(7900#)
        cx(k) = mpv(0) * 1000: cy(k) = mpv(1) * 1000: cz(k) = mpv(2) * 1000
        vol(k) = mpv(3) * 1000000000#
        best = 1E+30
        For i = 0 To UBound(keys)
            d = DistToSegment(cx(k), cy(k), cz(k), tubes(keys(i)))
            If d < best Then best = d: nearest(k) = keys(i)
        Next i
        dist(k) = best
    Next k
    ' largest body per tube
    Dim largest As Object
    Set largest = CreateObject("Scripting.Dictionary")
    For k = 0 To nB - 1
        If Not largest.Exists(nearest(k)) Then
            largest(nearest(k)) = k
        ElseIf vol(k) > vol(largest(nearest(k))) Then
            largest(nearest(k)) = k
        End If
    Next k
    Dim txt As String, t As Variant, dEnd As Double, tv As Double, isStub As Boolean
    For k = 0 To nB - 1
        If largest(nearest(k)) <> k Then
            t = tubes(nearest(k))
            dEnd = Dist3(cx(k), cy(k), cz(k), t(0), t(1), t(2))
            d = Dist3(cx(k), cy(k), cz(k), t(3), t(4), t(5))
            If d < dEnd Then dEnd = d
            tv = 0
            If tubeVol.Exists(nearest(k)) Then tv = tubeVol(nearest(k))
            isStub = (vol(k) <= STUB_MAX_MM3) And (tv > 0 And vol(k) <= STUB_MAX_FRACTION * tv) And (dEnd <= STUB_NODE_MM)
            Set swBody = bodies(k)
            txt = txt & "  " & IIf(isStub, "STUB  ", "EXTRA ") & swBody.Name & " at (" & Format(cx(k), "0.0") & "," & Format(cy(k), "0.0") & "," & _
                  Format(cz(k), "0.0") & ") mm, " & Format(vol(k), "0") & " mm3 (" & Format(IIf(tv > 0, vol(k) / tv * 100, 0), "0.0") & _
                  " % of tube " & nearest(k) & "), " & Format(dEnd, "0.0") & " mm from its nearest end node" & _
                  IIf(isStub, " -> delete", " -> NOT a stub, left alone") & vbCrLf
            If isStub Then stubs.Add swBody
        End If
    Next k
    Dim nNo As Long
    For i = 0 To UBound(keys)
        If Not largest.Exists(keys(i)) Then
            txt = txt & "  tube " & keys(i) & " has no body" & vbCrLf
            nNo = nNo + 1
        End If
    Next i
    If txt = "" Then txt = "  (none: one body per tube)" & vbCrLf
    FindStubs = txt
End Function

' One Delete/Keep Body feature removing the stubs; returns its name or "".
Private Function DeleteStubs(ByVal swModel As SldWorks.ModelDoc2, ByVal swFeatMgr As SldWorks.FeatureManager, _
                             ByVal stubs As Collection, ByVal cpm As SldWorks.CustomPropertyManager) As String
    Dim b As Variant, swBody As SldWorks.Body2, f As SldWorks.Feature, n As Long, nm As String, names As String
    swModel.ClearSelection2 True
    For Each b In stubs
        Set swBody = b
        names = names & swBody.Name & " "
        swBody.Select2 True, Nothing
    Next b
    Set f = swFeatMgr.InsertDeleteBody2(False)
    swModel.ClearSelection2 True
    If f Is Nothing Then Exit Function
    n = 1
    Do While Not FindFeatureDeep(swModel, "StubsDeleted_" & n) Is Nothing
        n = n + 1
    Loop
    nm = "StubsDeleted_" & n
    On Error Resume Next
    f.Name = nm
    On Error GoTo 0
    If Not cpm Is Nothing Then
        cpm.Add3 "TrimStubs_" & n, swCustomInfoType_e.swCustomInfoText, Left$(names, 250), _
                 swCustomPropertyAddOption_e.swCustomPropertyReplaceValue
    End If
    DeleteStubs = f.Name
End Function


' FindFeature that also looks at sub-features.
Private Function FindFeatureDeep(ByVal swModel As SldWorks.ModelDoc2, ByVal nm As String) As SldWorks.Feature
    Dim f As SldWorks.Feature, sf As SldWorks.Feature
    Set f = swModel.FirstFeature
    Do While Not f Is Nothing
        If StrComp(f.Name, nm, vbTextCompare) = 0 Then
            Set FindFeatureDeep = f
            Exit Function
        End If
        Set sf = f.GetFirstSubFeature
        Do While Not sf Is Nothing
            If StrComp(sf.Name, nm, vbTextCompare) = 0 Then
                Set FindFeatureDeep = sf
                Exit Function
            End If
            Set sf = sf.GetNextSubFeature
        Loop
        Set f = f.GetNextFeature
    Loop
End Function


Private Function FindFeature(ByVal swModel As SldWorks.ModelDoc2, ByVal nm As String) As SldWorks.Feature
    Dim f As SldWorks.Feature
    Set f = swModel.FirstFeature
    Do While Not f Is Nothing
        If StrComp(f.Name, nm, vbTextCompare) = 0 Then
            Set FindFeature = f
            Exit Function
        End If
        Set f = f.GetNextFeature
    Loop
    Set FindFeature = Nothing
End Function

' Read a text file whole and split it into lines; works for LF and CRLF.
Private Function ReadTextLines(ByVal path As String) As Variant
    Dim fnum As Integer, txt As String, arr() As String, k As Long
    fnum = FreeFile
    Open path For Binary Access Read As #fnum
    If LOF(fnum) > 0 Then
        txt = Space$(LOF(fnum))
        Get #fnum, , txt
    End If
    Close #fnum
    arr = Split(txt, vbLf)
    For k = 0 To UBound(arr)
        arr(k) = Replace(arr(k), vbCr, "")
    Next k
    ReadTextLines = arr
End Function

' Walk up from the .swp folder until params\car_params.txt is found.
Private Function RepoRootFromMacroPath() As String
    Dim p As String
    p = Application.SldWorks.GetCurrentMacroPathName
    If p <> "" Then
        p = Left$(p, InStrRev(p, "\") - 1)
        Do While InStr(p, "\") > 0
            If Dir(p & "\params\car_params.txt") <> "" Then
                RepoRootFromMacroPath = p
                Exit Function
            End If
            p = Left$(p, InStrRev(p, "\") - 1)
        Loop
    End If
    RepoRootFromMacroPath = CurDir$
End Function
