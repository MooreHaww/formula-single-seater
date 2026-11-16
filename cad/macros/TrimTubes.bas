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

Private Const MATCH_MM As Double = 12#     ' centroid to own centreline (real: 0.3 to 4.1 mm)
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
    ' Re-run guard: rows are skipped by their name Trim_<node>. If the part has trim
    ' features under any other name (SolidWorks renamed the structural members once),
    ' the "done" rows cannot be told apart, so stop instead of trimming twice.
    Dim ours As Long, foreign As String
    CountTrimFeatures swModel, ours, foreign
    If foreign <> "" Then
        MsgBox "This part has trim features that are not named Trim_<node>: " & Left$(foreign, 400) & vbCrLf & _
               "TrimTubes cannot tell which rows they belong to, so it stops. Nothing was changed." & vbCrLf & _
               "Rename them Trim_<node> (the node is in cad\frame\frame_trims.csv) or delete them, then run again.", vbExclamation
        Exit Sub
    End If
    Dim bodyOf As Object, unmatched As String, nBodies0 As Long
    Set bodyOf = MatchBodies(swPart, tubes, unmatched, nBodies0)
    Dim r As Long, ids As Variant, j As Long, nToDo As Long, nKept As Long, why As String
    For r = 1 To nRows
        If Not FindFeature(swModel, rowName(r)) Is Nothing Then
            rowState(r) = "kept"
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
        If pre = "" Then
            MsgBox "All " & nKept & " Trim_* features already exist. Nothing was changed.", vbInformation
        Else
            WriteReport reportFile, "NOTHING CHANGED (" & Format(Now, "yyyy-mm-dd hh:nn") & ")" & vbCrLf & vbCrLf & _
                        "Bodies: " & nBodies0 & ", tubes in CSV: " & tubes.Count & vbCrLf & "Unmatched: " & unmatched & vbCrLf & vbCrLf & pre
            MsgBox "No trim row can be made. Nothing was changed." & vbCrLf & "Report: " & reportFile, vbExclamation
        End If
        Exit Sub
    End If

    ' mass before
    Dim mp As SldWorks.MassProperty, mass0 As Double, mass1 As Double
    Set mp = swModel.Extension.CreateMassProperty
    If Not mp Is Nothing Then mass0 = mp.Mass

    ' --- 2. trims -------------------------------------------------------------------------
    Dim report As String, failures As String, allPass As Boolean, nDone As Long
    Dim bArr() As Object, tArr() As Object, nb As Long, nt As Long, bIds As Variant, tIds As Variant
    Dim trimType As String
    Dim f As SldWorks.Feature, modeTxt As String, err1 As String, dummy As String, dummyN As Long
    allPass = True
    For r = 1 To nRows
        If rowState(r) = "kept" Then
            report = report & "PASS  " & rowName(r) & ": existed, kept" & vbCrLf
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
        report = report & "PASS  " & rowName(r) & ": " & nt & " ends against " & nb & " boundary tube(s), " & modeTxt & vbCrLf
NextRow:
    Next r
    swModel.ClearSelection2 True
    swModel.ForceRebuild3 False

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
    summary = summary & PassFail(nBodies1 = nBodies0, allPass) & "  bodies: " & nBodies0 & " before, " & nBodies1 & " after (a trim must not split tubes)" & vbCrLf
    summary = summary & PassFail(mass1 <= mass0 And mass1 >= 38 And mass1 <= 46, allPass) & "  mass: " & Format(mass0, "0.00") & " kg before, " & _
              Format(mass1, "0.00") & " kg after (" & Format(mass1 - mass0, "+0.00;-0.00") & " kg; must not rise, 38 to 46)" & vbCrLf
    If lenMissing > 0 Or nFolders = 0 Then
        summary = summary & "INFO  cut length: LENGTH missing on " & lenMissing & " of " & nFolders & " cut-list items" & vbCrLf
    Else
        summary = summary & "INFO  cut length after trim: " & Format(cutLen_m, "0.00") & " m (" & nCut & " bodies in the cut list)" & vbCrLf
    End If

    ' --- 4. save ---------------------------------------------------------------------------
    Dim saved As Boolean, errs As Long, warns As Long
    saved = swModel.Save3(swSaveAsOptions_e.swSaveAsOptions_Silent, errs, warns)
    summary = summary & PassFail(saved, allPass) & "  saved: " & IIf(saved, swModel.GetPathName, "NOT saved (error " & errs & ")") & vbCrLf

    Dim full As String
    full = IIf(allPass, "ALL PASS", "SOME CHECKS FAILED") & "   (" & Format(Now, "yyyy-mm-dd hh:nn") & ", " & nDone & " trims made, " & _
           nKept & " kept, " & nRows & " in plan)" & vbCrLf & vbCrLf & summary & vbCrLf & _
           IIf(failures = "", "No failures.", "Failures:" & vbCrLf & failures) & _
           IIf(unmatched = "", "", vbCrLf & "Bodies or tubes without a match before trimming: " & unmatched) & _
           vbCrLf & "Trim features found by name before this run: " & ours & IIf(trimType = "", "", "; type name of the new ones: " & trimType)
    WriteReport reportFile, full
    Debug.Print full
    Dim shortTxt As String
    shortTxt = IIf(allPass, "ALL PASS", "SOME CHECKS FAILED") & ": " & nDone & " trims made, " & nKept & " kept, " & nRows & " in plan." & vbCrLf & vbCrLf & _
               Mid$(summary, Len(report) + 3)
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

' Trim features: ours (named Trim_*) and others (default name Trim/Extend<n>,
' or a weldment trim type name), listed by name.
Private Sub CountTrimFeatures(ByVal swModel As SldWorks.ModelDoc2, ByRef ours As Long, ByRef foreign As String)
    Dim f As SldWorks.Feature, tn As String
    Set f = swModel.FirstFeature
    Do While Not f Is Nothing
        tn = f.GetTypeName2
        If LCase$(Left$(f.Name, 5)) = "trim_" Then
            ours = ours + 1
        ElseIf LCase$(Left$(f.Name, 11)) = "trim/extend" Or InStr(1, tn, "Trim", vbTextCompare) > 0 Then
            foreign = foreign & f.Name & " (" & tn & "), "
        End If
        Set f = f.GetNextFeature
    Loop
End Sub

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
