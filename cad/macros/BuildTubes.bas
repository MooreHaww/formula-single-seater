Attribute VB_Name = "BuildTubes"
' ============================================================================
' BuildTubes.bas  (SolidWorks VBA macro module)
' STATUS: untested, needs the app. Every call checked against the installed
'         2026 SP2.1 interop DLLs (exact interface per variable); the
'         behaviour of the weldment calls is only known at run time.
' ----------------------------------------------------------------------------
' What it does (one click, after ImportFrameNodes)
'   1. For each of the seven 3D sketches made by ImportFrameNodes
'        FRAME_hoop, FRAME_hoop_brace, FRAME_sis, FRAME_bulkhead,
'        FRAME_sidepod, FRAME_front, FRAME_rear
'      creates one Structural Member from all (non-construction) segments of
'      that sketch: Standard "formula", Type "tube_round", Size <od>x<wall>
'      read per group from cad/frame/frame_tubes.csv (25.4x2.4 for hoop and
'      hoop_brace, 25.4x1.6 for the rest as filed), end miter, renamed
'      SM_<group>. An existing SM_<group> is kept and skipped.
'   2. Sets the part material to AISI 1020 from the "SOLIDWORKS Materials"
'      database (the name exists in the installed 2026 solidworks
'      materials.sldmat, density 7900 kg/m3; Plain Carbon Steel, 7800 kg/m3,
'      is also there and is used if AISI 1020 does not take).
'   3. Updates the weldment cut list.
'   4. One final message: segments per group vs 12/10/7/4/18/32/33, cut-list
'      bodies vs 116, total cut length vs the length sum in frame_tubes.csv
'      (41.88 m as filed, PASS within 5 %), mass vs 38 to 46 kg, each with
'      PASS or FAIL.
'   5. Saves the part. An unsaved part is saved as cad\chassis\chassis.SLDPRT
'      (the macro stops at the start if that file already exists, so nothing
'      is overwritten).
'   Order: first every check for all seven groups (sketch exists, has
'   segments, size in the CSV, profile file exists, save path free). Any
'   failure there stops with "Nothing was changed". Only then is the Weldment
'   feature inserted (only if the part has none) and the members built. A
'   group that fails while building stops with the group name and the
'   SolidWorks error text; members made so far stay, nothing is saved.
'
' Why a macro: in 2026 the Structural Member command shows every sketch
'   during selection, so a box select picks up lines of other groups. The API
'   takes the segments straight from one sketch, no selection involved.
'
' Repo root
'   Found by walking up from the folder of the running .swp until a folder
'   with params\car_params.txt is found. Save the .swp anywhere inside the
'   repo (cad\macros is the convention). Profiles are taken from
'   <repo>\cad\weldment_profiles\formula\tube_round\<size>.sldlfp.
'
' How to install and run: see cad/macros/README.md (Tools > Macro > New,
'   File > Import File, then Tools > Macro > Run on the .swp, not the .bas).
'
' Depends on run-time behaviour (not provable from the type library)
'   * Whether one group may hold a branched network (more than two segments
'     at a node). If the all-segments group is refused, the macro retries with
'     one group per segment in the same feature: always valid, but then no
'     miter inside the group; the Trim step does the joints. The message says
'     which mode each group got.
'   * Whether "" is accepted as the profile configuration name in
'     InsertStructuralWeldment5 (falls back to InsertStructuralWeldment4).
'   * Detecting an existing Weldment feature: PartDoc.IsWeldment stayed False
'     in the 2026 test with a Weldment feature and no members (a rerun added
'     Weldment1). The macro also looks for feature type "WeldmentFeature" (name
'     not confirmed from the type library) and for the default names Weldment,
'     Weldment1, ...; any of the three counts.
'   * The material database name "SOLIDWORKS Materials" (checked by reading
'     the material back; a mismatch is reported, not fatal).
'   * The cut-list feature type names "SolidBodyFolder" / "CutListFolder" and
'     the cut-list property "LENGTH" (resolved value in mm). If LENGTH is not
'     found the length check says so and FAILs.
'   * Late-bound: Feature.GetSpecificFeature2, Sketch.GetSketchSegments,
'     GetFirstSubFeature / GetNextSubFeature return Object or Variant.
'   Before the trim step the tubes overlap at the joints, so the mass and cut
'   length are slightly high; both limits allow for it.
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
        MsgBox "Open the chassis part with the FRAME_* sketches first.", vbExclamation
        Exit Sub
    End If
    If swModel.GetType <> swDocPART Then
        MsgBox "The active document must be a part.", vbExclamation
        Exit Sub
    End If
    Set swPart = swModel
    Set swFeatMgr = swModel.FeatureManager

    Dim repoRoot As String
    repoRoot = RepoRootFromMacroPath()
    Dim tubesFile As String, profDir As String, savePath As String
    tubesFile = repoRoot & "\cad\frame\frame_tubes.csv"
    profDir = repoRoot & "\cad\weldment_profiles\formula\tube_round\"
    If Dir(tubesFile) = "" Then
        MsgBox "Not found: " & tubesFile & ". Nothing was changed.", vbExclamation
        Exit Sub
    End If
    ' where to save: the part's own path, or cad\chassis\chassis.SLDPRT if unsaved
    savePath = swModel.GetPathName
    If savePath = "" Then
        savePath = repoRoot & "\cad\chassis\chassis.SLDPRT"
        If Dir(savePath) <> "" Then
            MsgBox "This part is not saved yet and " & savePath & " already exists. " & _
                   "Save this part under a name of your choice first (nothing was changed).", vbExclamation
            Exit Sub
        End If
    End If

    ' --- size per group and total centreline length from the CSV ---------------
    Dim sizes As Object
    Set sizes = CreateObject("Scripting.Dictionary")
    Dim lines As Variant, k As Long, ln As String, parts() As String, g As String, sz As String
    Dim csvLength_m As Double
    lines = ReadTextLines(tubesFile)
    For k = 1 To UBound(lines)
        ln = Trim$(lines(k))
        If ln <> "" And Left$(ln, 1) <> "#" Then
            parts = Split(ln, ",")
            If UBound(parts) >= 6 Then
                g = Trim$(parts(3))
                sz = Trim$(parts(4)) & "x" & Trim$(parts(5))
                csvLength_m = csvLength_m + Val(parts(6)) / 1000#
                If Not sizes.Exists(g) Then
                    sizes.Add g, sz
                ElseIf sizes(g) <> sz Then
                    MsgBox "Group " & g & " mixes tube sizes (" & sizes(g) & " and " & sz & ") in frame_tubes.csv. " & _
                           "One Structural Member needs one size; split the group in frame_layout.m. Nothing was changed.", vbExclamation
                    Exit Sub
                End If
            End If
        End If
    Next k

    ' --- 0. check everything for all seven groups before changing anything ---------
    Dim groupsOrder As Variant, expected As Variant
    groupsOrder = Array("hoop", "hoop_brace", "sis", "bulkhead", "sidepod", "front", "rear")
    expected = Array(12, 10, 7, 4, 18, 32, 33)
    Dim report As String, i As Long, allPass As Boolean
    Dim swSkFeat As SldWorks.Feature, swSketch As SldWorks.Sketch, swSM As SldWorks.Feature
    Dim segs As Variant, keep() As Object, nKeep As Long, j As Long
    Dim profPath As String, modeTxt As String, errTxt As String
    Dim segsByGroup(0 To 6) As Variant, profByGroup(0 To 6) As String, smExists(0 To 6) As Boolean
    allPass = True

    For i = 0 To UBound(groupsOrder)
        g = groupsOrder(i)
        Set swSkFeat = FindFeature(swModel, "FRAME_" & g)
        If swSkFeat Is Nothing Then
            StopNoChange g, "no sketch named FRAME_" & g & " (run ImportFrameNodes first)"
            Exit Sub
        End If
        ' segments of this one sketch (construction geometry left out)
        Set swSketch = swSkFeat.GetSpecificFeature2
        If swSketch Is Nothing Then
            StopNoChange g, "FRAME_" & g & " did not return a Sketch object"
            Exit Sub
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
            StopNoChange g, "FRAME_" & g & " has no segments"
            Exit Sub
        End If
        ReDim Preserve keep(0 To nKeep - 1)
        segsByGroup(i) = keep
        smExists(i) = Not FindFeature(swModel, "SM_" & g) Is Nothing
        If Not smExists(i) Then
            If Not sizes.Exists(g) Then
                StopNoChange g, "group not found in frame_tubes.csv"
                Exit Sub
            End If
            profByGroup(i) = profDir & sizes(g) & ".sldlfp"
            If Dir(profByGroup(i)) = "" Then
                StopNoChange g, "profile file not found: " & profByGroup(i)
                Exit Sub
            End If
        End If
    Next i

    ' --- weldment feature: only now, and only if the part has none yet --------------
    If Not HasWeldmentFeature(swModel, swPart) Then
        If swFeatMgr.InsertWeldmentFeature Is Nothing Then
            MsgBox "Could not insert the Weldment feature (Insert > Weldments > Weldment by hand, then rerun). " & _
                   "Nothing was changed.", vbExclamation
            Exit Sub
        End If
    End If

    ' --- 1. structural members ----------------------------------------------------
    For i = 0 To UBound(groupsOrder)
        g = groupsOrder(i)
        nKeep = UBound(segsByGroup(i)) + 1
        If smExists(i) Then
            modeTxt = "existed, kept"
        Else
            profPath = profByGroup(i)
            ' attempt 1: all segments in one group (miter between them)
            swModel.ClearSelection2 True
            Set swSM = MakeMember(swFeatMgr, profPath, segsByGroup(i), True)
            modeTxt = "one group"
            If swSM Is Nothing Then
                errTxt = CreateErrors(swFeatMgr)
                ' attempt 2: one group per segment, same feature
                swModel.ClearSelection2 True
                Set swSM = MakeMember(swFeatMgr, profPath, segsByGroup(i), False)
                modeTxt = "one group per segment (one group refused: " & errTxt & ")"
            End If
            If swSM Is Nothing Then
                StopMsg g, "Structural Member refused for " & nKeep & " segments, size " & sizes(g) & _
                           ". SolidWorks says: " & CreateErrors(swFeatMgr) & _
                           " (first attempt: " & errTxt & ")", report
                Exit Sub
            End If
            On Error Resume Next
            swSM.Name = "SM_" & g
            On Error GoTo 0
            If swSM.Name <> "SM_" & g Then modeTxt = modeTxt & ", NOT renamed (is " & swSM.Name & ")"
        End If
        report = report & PassFail(nKeep = expected(i), allPass) & "  SM_" & g & ": " & nKeep & _
                 " tubes (expected " & expected(i) & "), " & sizes(g) & ", " & modeTxt & vbCrLf
    Next i
    swModel.ClearSelection2 True
    swModel.ForceRebuild3 False

    ' --- 2. material ---------------------------------------------------------------
    Dim cfgName As String, dbOut As String, matName As String, matTxt As String
    cfgName = swModel.ConfigurationManager.ActiveConfiguration.Name
    swPart.SetMaterialPropertyName2 cfgName, MAT_DB, "AISI 1020"
    matName = swPart.GetMaterialPropertyName2(cfgName, dbOut)
    If StrComp(matName, "AISI 1020", vbTextCompare) <> 0 Then
        swPart.SetMaterialPropertyName2 cfgName, MAT_DB, "Plain Carbon Steel"
        matName = swPart.GetMaterialPropertyName2(cfgName, dbOut)
    End If
    If matName = "" Then
        matTxt = "FAIL  material: not set (set AISI 1020 by hand: right-click Material > SOLIDWORKS Materials > Steel)"
        allPass = False
    Else
        matTxt = "PASS  material: " & matName & " (" & dbOut & ")"
    End If
    swModel.ForceRebuild3 False

    ' --- 3. cut list: update, count bodies, sum LENGTH x count ------------------------
    Dim nBodies As Long, cutLen_m As Double, lenMissing As Long, nFolders As Long
    UpdateCutList swModel, nBodies, cutLen_m, lenMissing, nFolders

    ' --- 4. mass ------------------------------------------------------------------------
    Dim mp As SldWorks.MassProperty, mass_kg As Double
    Set mp = swModel.Extension.CreateMassProperty
    If Not mp Is Nothing Then mass_kg = mp.Mass

    Dim summary As String, lenOk As Boolean
    summary = report
    summary = summary & PassFail(nBodies = 116, allPass) & "  cut-list bodies: " & nBodies & " (expected 116, " & nFolders & " cut-list items)" & vbCrLf
    If lenMissing > 0 Or nFolders = 0 Then
        summary = summary & PassFail(False, allPass) & "  cut length: LENGTH property missing on " & lenMissing & _
                  " of " & nFolders & " cut-list items (check the cut list by hand)" & vbCrLf
    Else
        lenOk = Abs(cutLen_m - csvLength_m) <= 0.05 * csvLength_m
        summary = summary & PassFail(lenOk, allPass) & "  cut length: " & Format(cutLen_m, "0.00") & " m vs " & _
                  Format(csvLength_m, "0.00") & " m in frame_tubes.csv (" & Format(100 * (cutLen_m / csvLength_m - 1), "+0.0;-0.0") & " %, limit 5 %)" & vbCrLf
    End If
    summary = summary & PassFail(mass_kg >= 38 And mass_kg <= 46, allPass) & "  mass: " & Format(mass_kg, "0.0") & " kg (expected 38 to 46)" & vbCrLf
    summary = summary & matTxt & vbCrLf

    ' --- 5. save -------------------------------------------------------------------------
    Dim saved As Boolean, errs As Long, warns As Long, saveTxt As String
    If swModel.GetPathName = "" Then
        If Dir(repoRoot & "\cad\chassis", vbDirectory) = "" Then MkDir repoRoot & "\cad\chassis"
        saved = swModel.Extension.SaveAs3(savePath, swSaveAsVersion_e.swSaveAsCurrentVersion, _
                    swSaveAsOptions_e.swSaveAsOptions_Silent, Nothing, Nothing, errs, warns)
    Else
        saved = swModel.Save3(swSaveAsOptions_e.swSaveAsOptions_Silent, errs, warns)
    End If
    If saved Then saveTxt = "Saved: " & savePath Else saveTxt = "NOT saved (error " & errs & "): save by hand."

    MsgBox IIf(allPass, "ALL PASS", "SOME CHECKS FAILED") & vbCrLf & vbCrLf & summary & vbCrLf & saveTxt & vbCrLf & vbCrLf & _
           "Next: Trim/Extend (02_chassis.md step 7).", IIf(allPass, vbInformation, vbExclamation)
End Sub

' Build the groups and insert one Structural Member feature.
' oneGroup = True: every segment in a single group (end miter between them).
' oneGroup = False: one group per segment (always valid, no miter within).
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

' Update the cut list and total it: bodies, and sum of LENGTH (mm) x bodies per item.
Private Sub UpdateCutList(ByVal swModel As SldWorks.ModelDoc2, ByRef nBodies As Long, ByRef cutLen_m As Double, _
                          ByRef lenMissing As Long, ByRef nFolders As Long)
    Dim f As SldWorks.Feature, sf As SldWorks.Feature
    Dim swFolder As SldWorks.BodyFolder, cpm As SldWorks.CustomPropertyManager
    Dim valOut As String, resOut As String, wasRes As Boolean, linked As Boolean, cnt As Long
    ' first pass: update
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
    ' second pass: read the cut-list items under the solid-body folder
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

' Stop during the checks, before anything was changed in the part.
Private Sub StopNoChange(ByVal g As String, ByVal why As String)
    MsgBox "Stopped at group " & g & ": " & why & vbCrLf & vbCrLf & _
           "Nothing was changed (all checks run before the Weldment feature or any member is added).", vbExclamation
End Sub

' Stop while building, after some members may have been added.
Private Sub StopMsg(ByVal g As String, ByVal why As String, ByVal report As String)
    MsgBox "Stopped at group " & g & ": " & why & vbCrLf & vbCrLf & _
           "Members built before the stop are kept, the part is NOT saved:" & vbCrLf & _
           IIf(report = "", "(none; the Weldment feature may have been added)", report), vbExclamation
End Sub

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
