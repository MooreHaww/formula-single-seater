Attribute VB_Name = "BuildTubes"
' ============================================================================
' BuildTubes.bas  (SolidWorks VBA macro module)
' STATUS: ran in SolidWorks 2026 SP2.1 Student (2026-11-16): 6 of 7 groups
'         built with the one-group-per-segment fallback, rear refused (cause:
'         a duplicate rear rail in the data, fixed in frame_layout.m). This
'         version (carry-on, per-segment fallback, report file) is untested.
' ----------------------------------------------------------------------------
' What it does (one click, after ImportFrameNodes)
'   1. Checks first, changes nothing: the part, cad/frame/*.csv, the save
'      path, and per group the FRAME_<group> sketch, its segments, its tube
'      size in the CSV and the profile file. A group that fails a check is
'      reported and skipped; the others go on. If no group can be built the
'      macro stops with "Nothing was changed".
'   2. Inserts the Weldment feature, only if the part has none yet.
'   3. Per group, one Structural Member from that sketch's segments: Standard
'      "formula", Type "tube_round", Size <od>x<wall> from frame_tubes.csv,
'      end miter, named SM_<group>. Three attempts:
'        A  all segments in one group (miter between them);
'        B  one group per segment, still one feature SM_<group> (no miter);
'        C  each segment as its own feature SM_<group>_<tube id>; every
'           segment that fails even alone is listed with its CSV tube id,
'           node ids and length. The group goes on with the rest.
'   4. Material AISI 1020 ("SOLIDWORKS Materials"; Plain Carbon Steel if
'      AISI 1020 does not take).
'   5. Updates the cut list.
'   6. Saves the part (also when some checks failed, so a rerun only adds what
'      is missing). An unsaved part becomes cad\chassis\chassis.SLDPRT; the
'      macro stops at the start, changing nothing, if that file exists.
'   7. Final message: PASS/FAIL per group (segments built vs tubes in the
'      CSV), cut-list bodies vs tubes in the CSV, total cut length vs the CSV
'      sum (within 5 %), mass 38 to 46 kg, material, save; then every failure.
'      Expected numbers come from frame_tubes.csv, not from this file. The
'      full report (a message box shows about 1000 characters) is also written
'      to cad\chassis\build_tubes_report.txt and to the Immediate window.
'
' Repo root
'   Found by walking up from the folder of the running .swp until a folder
'   with params\car_params.txt is found. Save the .swp anywhere inside the
'   repo (cad\macros is the convention). Profiles are taken from
'   <repo>\cad\weldment_profiles\formula\tube_round\<size>.sldlfp.
'
' How to install and run: see cad/macros/README.md. All modules may live in
'   one macro project (repo_macros.swp); run BuildTubes.main from it.
'
' Depends on run-time behaviour (not provable from the type library)
'   * Attempt A: the 2026 run refused one group for every frame group (each
'     branched), reported "(no message)"; B worked for six groups.
'   * "" as the profile configuration name in InsertStructuralWeldment5
'     (falls back to InsertStructuralWeldment4).
'   * Detecting an existing Weldment feature: PartDoc.IsWeldment stayed False
'     with a Weldment feature and no members, so the macro also looks for type
'     "WeldmentFeature" (not confirmed from the type library) and for the
'     default names Weldment, Weldment1, ...
'   * Material database name "SOLIDWORKS Materials" (read back to check).
'   * Cut-list type names "SolidBodyFolder" / "CutListFolder" and the cut-list
'     property "LENGTH" (resolved value in mm).
'   * Late-bound: Feature.GetSpecificFeature2, Sketch.GetSketchSegments, the
'     sub-feature walk, and SketchLine.GetStartPoint2 / GetEndPoint2.
'   Before the trim the tubes overlap at the joints, so mass and cut length
'   read slightly high; the limits allow for it.
' ============================================================================
Option Explicit

Private Const MAT_DB As String = "SOLIDWORKS Materials"

Sub main()
    Dim swApp As SldWorks.SldWorks
    Dim swModel As SldWorks.ModelDoc2
    Dim swPart As SldWorks.PartDoc
    Dim swFeatMgr As SldWorks.FeatureManager
    Set swApp = Application.SldWorks
    Set swModel = swApp.ActiveDoc
    If swModel Is Nothing Then
        MsgBox "Open the chassis part with the FRAME_* sketches first. Nothing was changed.", vbExclamation
        Exit Sub
    End If
    If swModel.GetType <> swDocPART Then
        MsgBox "The active document must be a part. Nothing was changed.", vbExclamation
        Exit Sub
    End If
    Set swPart = swModel
    Set swFeatMgr = swModel.FeatureManager

    Dim repoRoot As String
    repoRoot = RepoRootFromMacroPath()
    Dim tubesFile As String, nodesFile As String, profDir As String, savePath As String, reportFile As String
    tubesFile = repoRoot & "\cad\frame\frame_tubes.csv"
    nodesFile = repoRoot & "\cad\frame\frame_nodes.csv"
    profDir = repoRoot & "\cad\weldment_profiles\formula\tube_round\"
    reportFile = repoRoot & "\cad\chassis\build_tubes_report.txt"
    If Dir(tubesFile) = "" Or Dir(nodesFile) = "" Then
        MsgBox "Not found: " & tubesFile & " or " & nodesFile & ". Nothing was changed.", vbExclamation
        Exit Sub
    End If
    savePath = swModel.GetPathName
    If savePath = "" Then
        savePath = repoRoot & "\cad\chassis\chassis.SLDPRT"
        If Dir(savePath) <> "" Then
            MsgBox "This part is not saved yet and " & savePath & " already exists. " & _
                   "Save this part under a name of your choice first. Nothing was changed.", vbExclamation
            Exit Sub
        End If
    End If

    ' --- read the CSVs -------------------------------------------------------------
    ' nodes: name -> Array(x, y, z) in mm
    Dim nodes As Object
    Set nodes = CreateObject("Scripting.Dictionary")
    Dim lines As Variant, k As Long, ln As String, parts() As String, g As String, sz As String
    lines = ReadTextLines(nodesFile)
    For k = 1 To UBound(lines)
        ln = Trim$(lines(k))
        If ln <> "" And Left$(ln, 1) <> "#" Then
            parts = Split(ln, ",")
            If UBound(parts) >= 3 Then nodes(Trim$(parts(0))) = Array(Val(parts(1)), Val(parts(2)), Val(parts(3)))
        End If
    Next k
    ' tubes: sizes and counts per group, "a|b" -> tube text, totals
    Dim sizes As Object, expCount As Object, tubeByPair As Object, badSize As Object
    Set sizes = CreateObject("Scripting.Dictionary")
    Set expCount = CreateObject("Scripting.Dictionary")
    Set tubeByPair = CreateObject("Scripting.Dictionary")
    Set badSize = CreateObject("Scripting.Dictionary")
    Dim csvLength_m As Double, csvTubes As Long, groupsOrder As Collection
    Set groupsOrder = New Collection
    Dim known As Variant
    known = Array("hoop", "hoop_brace", "sis", "bulkhead", "sidepod", "front", "rear")
    For k = 0 To UBound(known)
        groupsOrder.Add known(k)
        expCount(known(k)) = 0
    Next k
    lines = ReadTextLines(tubesFile)
    For k = 1 To UBound(lines)
        ln = Trim$(lines(k))
        If ln <> "" And Left$(ln, 1) <> "#" Then
            parts = Split(ln, ",")
            If UBound(parts) >= 6 Then
                g = Trim$(parts(3))
                sz = Trim$(parts(4)) & "x" & Trim$(parts(5))
                csvLength_m = csvLength_m + Val(parts(6)) / 1000#
                csvTubes = csvTubes + 1
                If Not expCount.Exists(g) Then
                    expCount(g) = 0
                    groupsOrder.Add g
                End If
                expCount(g) = expCount(g) + 1
                If Not sizes.Exists(g) Then
                    sizes(g) = sz
                ElseIf sizes(g) <> sz Then
                    badSize(g) = sizes(g) & " and " & sz
                End If
                tubeByPair(PairKey(Trim$(parts(1)), Trim$(parts(2)))) = Trim$(parts(0)) & " (" & Trim$(parts(1)) & " - " & _
                    Trim$(parts(2)) & ", " & Format(Val(parts(6)), "0") & " mm)"
            End If
        End If
    Next k

    ' --- 0. checks per group, nothing changed yet ------------------------------------
    Dim nG As Long, i As Long, j As Long
    nG = groupsOrder.Count
    Dim gName() As String, segsByGroup() As Variant, profByGroup() As String
    Dim smExists() As Boolean, buildable() As Boolean, failTxt() As String
    ReDim gName(1 To nG): ReDim segsByGroup(1 To nG): ReDim profByGroup(1 To nG)
    ReDim smExists(1 To nG): ReDim buildable(1 To nG): ReDim failTxt(1 To nG)
    Dim smOther() As String
    ReDim smOther(1 To nG)
    Dim swSkFeat As SldWorks.Feature, swSketch As SldWorks.Sketch
    Dim segs As Variant, keep() As Object, nKeep As Long, nToBuild As Long, nExisting As Long
    For i = 1 To nG
        g = groupsOrder(i): gName(i) = g
        smExists(i) = Not FindFeature(swModel, "SM_" & g) Is Nothing
        Set swSkFeat = FindFeature(swModel, "FRAME_" & g)
        If swSkFeat Is Nothing Then
            failTxt(i) = "no sketch named FRAME_" & g & " (run ImportFrameNodes)"
            GoTo NextCheck
        End If
        ' A member renamed by SolidWorks (e.g. "25.4x2.4 (1)") is still a child of its sketch
        If Not smExists(i) Then
            smOther(i) = MembersFromSketch(swSkFeat)
            smExists(i) = (smOther(i) <> "")
        End If
        Set swSketch = swSkFeat.GetSpecificFeature2
        If swSketch Is Nothing Then
            failTxt(i) = "FRAME_" & g & " did not return a Sketch object"
            GoTo NextCheck
        End If
        segs = swSketch.GetSketchSegments
        nKeep = 0
        If Not IsEmpty(segs) Then
            ReDim keep(0 To UBound(segs))
            For j = 0 To UBound(segs)
                If Not segs(j).ConstructionGeometry Then
                    Set keep(nKeep) = segs(j)
                    nKeep = nKeep + 1
                End If
            Next j
        End If
        If nKeep = 0 Then
            failTxt(i) = "FRAME_" & g & " has no segments"
            GoTo NextCheck
        End If
        ReDim Preserve keep(0 To nKeep - 1)
        segsByGroup(i) = keep
        If smExists(i) Then
            nExisting = nExisting + 1
            GoTo NextCheck
        End If
        If Not sizes.Exists(g) Then
            failTxt(i) = "group not in frame_tubes.csv"
            GoTo NextCheck
        End If
        If nKeep <> expCount(g) Then
            failTxt(i) = "FRAME_" & g & " has " & nKeep & " segments but frame_tubes.csv has " & expCount(g) & _
                         " tubes: the sketch is out of date (run ImportFrameNodes on a clean part)"
            GoTo NextCheck
        End If
        If badSize.Exists(g) Then
            failTxt(i) = "mixes tube sizes " & badSize(g) & " in frame_tubes.csv (split the group in frame_layout.m)"
            GoTo NextCheck
        End If
        profByGroup(i) = profDir & sizes(g) & ".sldlfp"
        If Dir(profByGroup(i)) = "" Then
            failTxt(i) = "profile file not found: " & profByGroup(i)
            GoTo NextCheck
        End If
        buildable(i) = True
        nToBuild = nToBuild + 1
NextCheck:
    Next i

    If nToBuild = 0 Then
        Dim pre As String
        For i = 1 To nG
            If failTxt(i) <> "" Then pre = pre & "  " & gName(i) & ": " & failTxt(i) & vbCrLf
        Next i
        If pre = "" Then
            MsgBox "All " & nExisting & " structural members already exist (found by name SM_<group> or as a child of FRAME_<group>); nothing to build. Nothing was changed.", vbInformation
        Else
            MsgBox "No group can be built. Nothing was changed." & vbCrLf & vbCrLf & pre, vbExclamation
        End If
        Exit Sub
    End If

    ' --- 2. weldment feature: only now, and only if the part has none ----------------
    If Not HasWeldmentFeature(swModel, swPart) Then
        If swFeatMgr.InsertWeldmentFeature Is Nothing Then
            MsgBox "Could not insert the Weldment feature (Insert > Weldments > Weldment by hand, then rerun). " & _
                   "Nothing was changed.", vbExclamation
            Exit Sub
        End If
    End If

    ' --- 3. structural members ----------------------------------------------------------
    Dim report As String, failures As String, allPass As Boolean, built As Long
    Dim swSM As SldWorks.Feature, modeTxt As String, errA As String, errB As String
    Dim one(0 To 0) As Object, nOk As Long, badSegs As String, segName As String
    allPass = True
    For i = 1 To nG
        g = gName(i)
        If smExists(i) Then
            report = report & PassFail(UBound(segsByGroup(i)) + 1 = expCount(g), allPass) & "  SM_" & g & ": existed" & IIf(smOther(i) = "", "", " as " & smOther(i)) & ", kept (" & _
                     UBound(segsByGroup(i)) + 1 & " segments, " & expCount(g) & " tubes in CSV)" & vbCrLf
            GoTo NextGroup
        End If
        If Not buildable(i) Then
            report = report & "FAIL  " & g & ": not built, " & failTxt(i) & vbCrLf
            failures = failures & "- " & g & ": " & failTxt(i) & vbCrLf
            allPass = False
            GoTo NextGroup
        End If
        nKeep = UBound(segsByGroup(i)) + 1

        ' A: one group
        swModel.ClearSelection2 True
        Set swSM = MakeMember(swFeatMgr, profByGroup(i), segsByGroup(i), True)
        modeTxt = "one group"
        If swSM Is Nothing Then
            errA = CreateErrors(swFeatMgr)
            ' B: one group per segment, one feature
            swModel.ClearSelection2 True
            Set swSM = MakeMember(swFeatMgr, profByGroup(i), segsByGroup(i), False)
            modeTxt = "one group per segment"
        End If
        If Not swSM Is Nothing Then
            RenameFeature swSM, "SM_" & g, modeTxt
            nOk = nKeep
        Else
            ' C: each segment alone, as its own feature; list the ones that fail
            errB = CreateErrors(swFeatMgr)
            modeTxt = "segment by segment (one feature refused: " & errB & ")"
            nOk = 0: badSegs = ""
            For j = 0 To nKeep - 1
                Set one(0) = segsByGroup(i)(j)
                segName = SegmentLabel(segsByGroup(i)(j), nodes, tubeByPair)
                swModel.ClearSelection2 True
                Set swSM = MakeMember(swFeatMgr, profByGroup(i), one, True)
                If swSM Is Nothing Then
                    badSegs = badSegs & "    " & segName & ": " & CreateErrors(swFeatMgr) & vbCrLf
                Else
                    RenameFeature swSM, "SM_" & g & "_" & Split(segName, " ")(0), modeTxt
                    nOk = nOk + 1
                End If
            Next j
            If badSegs <> "" Then
                failures = failures & "- " & g & ": " & nKeep - nOk & " of " & nKeep & " segments refused even alone:" & vbCrLf & badSegs
            End If
        End If
        built = built + nOk
        report = report & PassFail(nOk = expCount(g) And nKeep = expCount(g), allPass) & "  SM_" & g & ": " & nOk & " of " & nKeep & _
                 " segments built (" & expCount(g) & " tubes in CSV), " & sizes(g) & ", " & modeTxt & vbCrLf
NextGroup:
    Next i
    swModel.ClearSelection2 True
    swModel.ForceRebuild3 False

    ' --- 4. material -------------------------------------------------------------------
    Dim cfgName As String, dbOut As String, matName As String, matTxt As String
    cfgName = swModel.ConfigurationManager.ActiveConfiguration.Name
    swPart.SetMaterialPropertyName2 cfgName, MAT_DB, "AISI 1020"
    matName = swPart.GetMaterialPropertyName2(cfgName, dbOut)
    If StrComp(matName, "AISI 1020", vbTextCompare) <> 0 Then
        swPart.SetMaterialPropertyName2 cfgName, MAT_DB, "Plain Carbon Steel"
        matName = swPart.GetMaterialPropertyName2(cfgName, dbOut)
    End If
    If matName = "" Then
        matTxt = "FAIL  material: not set (right-click Material > SOLIDWORKS Materials > Steel > AISI 1020)"
        failures = failures & "- material not set" & vbCrLf
        allPass = False
    Else
        matTxt = "PASS  material: " & matName & " (" & dbOut & ")"
    End If
    swModel.ForceRebuild3 False

    ' --- 5. cut list, mass ----------------------------------------------------------------
    Dim nBodies As Long, cutLen_m As Double, lenMissing As Long, nFolders As Long
    UpdateCutList swModel, nBodies, cutLen_m, lenMissing, nFolders
    Dim mp As SldWorks.MassProperty, mass_kg As Double
    Set mp = swModel.Extension.CreateMassProperty
    If Not mp Is Nothing Then mass_kg = mp.Mass

    Dim summary As String, lenOk As Boolean
    summary = report
    summary = summary & PassFail(nBodies = csvTubes, allPass) & "  cut-list bodies: " & nBodies & " (" & csvTubes & _
              " tubes in CSV, " & nFolders & " cut-list items)" & vbCrLf
    If lenMissing > 0 Or nFolders = 0 Then
        summary = summary & PassFail(False, allPass) & "  cut length: LENGTH property missing on " & lenMissing & _
                  " of " & nFolders & " cut-list items" & vbCrLf
        failures = failures & "- cut length could not be read (LENGTH property)" & vbCrLf
    Else
        lenOk = Abs(cutLen_m - csvLength_m) <= 0.05 * csvLength_m
        summary = summary & PassFail(lenOk, allPass) & "  cut length: " & Format(cutLen_m, "0.00") & " m vs " & _
                  Format(csvLength_m, "0.00") & " m in CSV (" & Format(100 * (cutLen_m / csvLength_m - 1), "+0.0;-0.0") & " %, limit 5 %)" & vbCrLf
    End If
    summary = summary & PassFail(mass_kg >= 38 And mass_kg <= 46, allPass) & "  mass: " & Format(mass_kg, "0.0") & " kg (expected 38 to 46)" & vbCrLf
    summary = summary & matTxt & vbCrLf

    ' --- 6. save ---------------------------------------------------------------------------
    Dim saved As Boolean, errs As Long, warns As Long, saveTxt As String
    If swModel.GetPathName = "" Then
        If Dir(repoRoot & "\cad\chassis", vbDirectory) = "" Then MkDir repoRoot & "\cad\chassis"
        saved = swModel.Extension.SaveAs3(savePath, swSaveAsVersion_e.swSaveAsCurrentVersion, _
                    swSaveAsOptions_e.swSaveAsOptions_Silent, Nothing, Nothing, errs, warns)
    Else
        saved = swModel.Save3(swSaveAsOptions_e.swSaveAsOptions_Silent, errs, warns)
    End If
    If saved Then
        saveTxt = "PASS  saved: " & savePath
    Else
        saveTxt = "FAIL  NOT saved (error " & errs & "): save by hand."
        allPass = False
    End If
    summary = summary & saveTxt & vbCrLf

    ' --- 7. report ----------------------------------------------------------------------------
    Dim full As String
    full = IIf(allPass, "ALL PASS", "SOME CHECKS FAILED") & "   (" & Format(Now, "yyyy-mm-dd hh:nn") & ", " & savePath & ")" & vbCrLf & vbCrLf & _
           summary & vbCrLf & IIf(failures = "", "No failures.", "Failures:" & vbCrLf & failures)
    WriteReport reportFile, full
    Debug.Print full
    If Len(full) > 900 Then full = Left$(full, 900) & vbCrLf & "... (cut; full text in " & reportFile & ")"
    MsgBox full & vbCrLf & vbCrLf & "Report: " & reportFile & vbCrLf & "Next: Trim/Extend (02_chassis.md step 7).", _
           IIf(allPass, vbInformation, vbExclamation)
End Sub

' Build the groups and insert one Structural Member feature.
' oneGroup = True: every segment in a single group (end miter between them).
' oneGroup = False: one group per segment (no miter within).
Private Function MakeMember(ByVal swFeatMgr As SldWorks.FeatureManager, ByVal profPath As String, _
                            ByVal segsArr As Variant, ByVal oneGroup As Boolean) As SldWorks.Feature
    Dim swGroup As SldWorks.StructuralMemberGroup
    Dim grpArr() As Object, n As Long, k As Long
    Dim one(0 To 0) As Object
    If oneGroup Then
        ReDim grpArr(0 To 0)
        Set swGroup = swFeatMgr.CreateStructuralMemberGroup
        swGroup.Segments = segsArr
        swGroup.ApplyCornerTreatment = True
        swGroup.CornerTreatmentType = swSolidworksWeldmentEndCondOptions_e.swEndConditionMiter
        Set grpArr(0) = swGroup
    Else
        n = UBound(segsArr) + 1
        ReDim grpArr(0 To n - 1)
        For k = 0 To n - 1
            Set one(0) = segsArr(k)
            Set swGroup = swFeatMgr.CreateStructuralMemberGroup
            swGroup.Segments = one
            swGroup.ApplyCornerTreatment = False
            Set grpArr(k) = swGroup
        Next k
    End If
    Dim groupsVar As Variant
    groupsVar = grpArr
    Dim f As SldWorks.Feature
    Set f = swFeatMgr.InsertStructuralWeldment5(profPath, swConnectedSegmentsOption_e.swConnectedSegments_SimpleCut, _
                                                True, groupsVar, "")
    If f Is Nothing Then
        Set f = swFeatMgr.InsertStructuralWeldment4(profPath, swConnectedSegmentsOption_e.swConnectedSegments_SimpleCut, _
                                                    True, groupsVar)
    End If
    Set MakeMember = f
End Function

' Names of the features built from this sketch (structural members), "" if none.
Private Function MembersFromSketch(ByVal skFeat As SldWorks.Feature) As String
    Dim kids As Variant, k As Long, s As String, kf As SldWorks.Feature
    kids = skFeat.GetChildren
    If IsArray(kids) Then
        For k = 0 To UBound(kids)
            Set kf = kids(k)
            If Not kf Is Nothing Then s = s & IIf(s = "", "", ", ") & kf.Name
        Next k
    End If
    MembersFromSketch = s
End Function

Private Sub RenameFeature(ByVal f As SldWorks.Feature, ByVal nm As String, ByRef modeTxt As String)
    On Error Resume Next
    f.Name = nm
    On Error GoTo 0
    If f.Name <> nm Then modeTxt = modeTxt & ", " & f.Name & " NOT renamed to " & nm
End Sub

' "tube id (node_a - node_b, length mm)" from the CSV, found by matching the
' segment's end points to the node coordinates (0.5 mm), else coordinates.
Private Function SegmentLabel(ByVal seg As Object, ByVal nodes As Object, ByVal tubeByPair As Object) As String
    Dim swSeg As SldWorks.SketchSegment, swLine As SldWorks.SketchLine
    Dim p1 As SldWorks.SketchPoint, p2 As SldWorks.SketchPoint
    Dim a As String, b As String
    Set swSeg = seg
    If swSeg.GetType <> swSketchSegments_e.swSketchLINE Then
        SegmentLabel = "non-line segment, length " & Format(swSeg.GetLength * 1000, "0") & " mm"
        Exit Function
    End If
    Set swLine = seg
    Set p1 = swLine.GetStartPoint2
    Set p2 = swLine.GetEndPoint2
    a = NearestNode(p1.X * 1000, p1.Y * 1000, p1.Z * 1000, nodes)
    b = NearestNode(p2.X * 1000, p2.Y * 1000, p2.Z * 1000, nodes)
    If a <> "" And b <> "" And tubeByPair.Exists(PairKey(a, b)) Then
        SegmentLabel = tubeByPair(PairKey(a, b))
    Else
        SegmentLabel = "unmatched (" & Format(p1.X * 1000, "0") & "," & Format(p1.Y * 1000, "0") & "," & Format(p1.Z * 1000, "0") & _
                       ")-(" & Format(p2.X * 1000, "0") & "," & Format(p2.Y * 1000, "0") & "," & Format(p2.Z * 1000, "0") & _
                       ") mm, nodes " & IIf(a = "", "?", a) & " / " & IIf(b = "", "?", b) & ", " & Format(swSeg.GetLength * 1000, "0") & " mm"
    End If
End Function

Private Function NearestNode(ByVal x As Double, ByVal y As Double, ByVal z As Double, ByVal nodes As Object) As String
    Dim key As Variant, p As Variant
    For Each key In nodes.Keys
        p = nodes(key)
        If Abs(p(0) - x) < 0.5 And Abs(p(1) - y) < 0.5 And Abs(p(2) - z) < 0.5 Then
            NearestNode = CStr(key)
            Exit Function
        End If
    Next key
End Function

Private Function PairKey(ByVal a As String, ByVal b As String) As String
    If a < b Then PairKey = a & "|" & b Else PairKey = b & "|" & a
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

' True if the part already has a Weldment feature. PartDoc.IsWeldment alone is
' not enough: in the 2026 test it stayed False with a Weldment feature and no
' members, and a rerun inserted a second one (Weldment1). So also look for the
' feature by type name ("WeldmentFeature", not confirmed from the type library)
' and by its default name (Weldment, Weldment1, ...).
Private Function HasWeldmentFeature(ByVal swModel As SldWorks.ModelDoc2, ByVal swPart As SldWorks.PartDoc) As Boolean
    If swPart.IsWeldment Then HasWeldmentFeature = True: Exit Function
    Dim f As SldWorks.Feature, nm As String
    Set f = swModel.FirstFeature
    Do While Not f Is Nothing
        If f.GetTypeName2 = "WeldmentFeature" Then HasWeldmentFeature = True: Exit Function
        nm = f.Name
        If StrComp(Left$(nm, 8), "Weldment", vbTextCompare) = 0 Then
            If Len(nm) = 8 Then HasWeldmentFeature = True: Exit Function
            If IsNumeric(Mid$(nm, 9)) Then HasWeldmentFeature = True: Exit Function
        End If
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
