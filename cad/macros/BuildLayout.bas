Attribute VB_Name = "BuildLayout"
' ============================================================================
' BuildLayout.bas  (SolidWorks VBA macro module)
' STATUS: untested, needs the app. Every call checked against the installed
'         2026 SP2.1 interop DLLs (exact interface per variable).
' ----------------------------------------------------------------------------
' What it does (one click, in an EMPTY new part, or with nothing open)
'   Builds the master layout cad/layout/master_layout.SLDPRT from
'   params/car_params.txt, the reference geometry everything else mates to.
'   Car coordinates are used directly as SolidWorks coordinates, the same as
'   ImportFrameNodes, BuildTubes and the build123d STEP parts:
'   X rearward from the front axle, Y to the right, Z up from the ground.
'   So the default planes become:
'       Front Plane (XY, Z = 0) -> GROUND
'       Top Plane   (XZ, Y = 0) -> CENTRE
'       Right Plane (YZ, X = 0) -> FRONT_AXLE
'   1. Checks first, changes nothing: car_params.txt is found and has every
'      value below; the active part has no GROUND feature yet (a built layout
'      is never built twice). Stops with "Nothing was changed" otherwise.
'   2. Links car_params.txt as the equation file (Tools > Equations > Link).
'   3. Planes, offset and checked by their actual position (a plane that
'      lands on the wrong side is rebuilt flipped):
'       REAR_AXLE  X = wheelbase        MAIN_HOOP  X = main_hoop_x
'       FRONT_HOOP X = front_hoop_x     WHEEL_CENTRE_HEIGHT  Z = tyre_rolling_radius
'      and each offset is tied to its global variable by an equation, so a
'      new wheelbase in car_params.txt moves REAR_AXLE on rebuild.
'   4. Axes FRONT_AXLE_AXIS and REAR_AXLE_AXIS (axle plane x wheel-centre plane).
'   5. Hardpoints: two 3D sketches HP_front_right and HP_rear_right with one
'      point per f_* / r_* hardpoint triple in car_params.txt (right side,
'      the left comes from mirroring the corner sub-assembly), and one named
'      reference point per sketch point, HP_<name> (e.g. HP_f_lwb_in_fwd),
'      so the assembly can mate to them by name.
'   6. Saves as cad\layout\master_layout.SLDPRT (if the part is unsaved) and
'      writes cad\layout\build_layout_report.txt. Every step carries on past a
'      failure and lists it.
'
' Not in this version (scriptable, planned once v1 has run): the WHEELS,
' SIDE_LAYOUT, TOP_LAYOUT, BODY_SECTIONS, FW/RW_POSITION sketches and the
' A to D configurations of 01_master_layout.md steps 6 to 10. Nothing in the
' assembly macro depends on them. The hardpoint points are placed by value:
' after a hardpoint change, build a fresh layout.
'
' Depends on run-time behaviour (not provable from the type library)
'   * The offset dimension of a plane is named D1@<plane> (used in the equations).
'   * InsertRefPlane offsets along the reference plane's normal; the macro
'     reads the plane's position back (RefPlane.Transform) and flips if needed.
'   * InsertReferencePoint(swRefPointSketchPoint) on a selected 3D-sketch point.
'   * InsertReferencePoint returns one feature or an array of them; both handled.
' ============================================================================
Option Explicit

Private swApp As SldWorks.SldWorks
Private swModel As SldWorks.ModelDoc2
Private report As String
Private failures As String
Private allPass As Boolean

Sub main()
    Set swApp = Application.SldWorks
    report = "": failures = "": allPass = True

    ' --- 1. checks -------------------------------------------------------------------
    Dim repoRoot As String, paramsFile As String, reportFile As String, savePath As String
    repoRoot = RepoRootFromMacroPath()
    paramsFile = repoRoot & "\params\car_params.txt"
    reportFile = repoRoot & "\cad\layout\build_layout_report.txt"
    savePath = repoRoot & "\cad\layout\master_layout.SLDPRT"
    If Dir(paramsFile) = "" Then
        MsgBox "Missing " & paramsFile & ". Nothing was changed.", vbExclamation
        Exit Sub
    End If
    Dim P As Object
    Set P = ReadParams(paramsFile)
    Dim need As Variant, k As Long, missing As String
    need = Array("wheelbase", "main_hoop_x", "front_hoop_x", "tyre_rolling_radius")
    For k = 0 To UBound(need)
        If Not P.Exists(need(k)) Then missing = missing & need(k) & " "
    Next k
    Dim hpFront As Collection, hpRear As Collection
    Set hpFront = HardpointNames(P, "f_")
    Set hpRear = HardpointNames(P, "r_")
    If hpFront.Count = 0 Then missing = missing & "f_*_x/_y/_z hardpoints "
    If hpRear.Count = 0 Then missing = missing & "r_*_x/_y/_z hardpoints "
    If missing <> "" Then
        MsgBox "car_params.txt has no numeric value for: " & missing & vbCrLf & "Nothing was changed.", vbExclamation
        Exit Sub
    End If

    Set swModel = swApp.ActiveDoc
    If swModel Is Nothing Then
        Dim tmpl As String
        tmpl = swApp.GetUserPreferenceStringValue(swUserPreferenceStringValue_e.swDefaultTemplatePart)
        Set swModel = swApp.NewDocument(tmpl, 0, 0#, 0#)
        If swModel Is Nothing Then
            MsgBox "No part open and no new part could be made from the default template (" & tmpl & "). Nothing was changed.", vbExclamation
            Exit Sub
        End If
    End If
    If swModel.GetType <> swDocPART Then
        MsgBox "The active document must be a new, empty part. Nothing was changed.", vbExclamation
        Exit Sub
    End If
    If Not FindFeature(swModel, "GROUND") Is Nothing Then
        MsgBox "This part already has a GROUND plane: the layout is built. Open a new part to build a fresh one. Nothing was changed.", vbExclamation
        Exit Sub
    End If
    Dim defPlanes As Collection
    Set defPlanes = FirstRefPlanes(swModel, 3)
    If defPlanes.Count < 3 Then
        MsgBox "Could not find the three default planes. Nothing was changed.", vbExclamation
        Exit Sub
    End If

    ' --- 2. equation file ----------------------------------------------------------------
    Dim eqMgr As SldWorks.EquationMgr, linked As Boolean
    Set eqMgr = swModel.GetEquationMgr
    On Error Resume Next
    eqMgr.FilePath = paramsFile
    eqMgr.LinkToFile = True
    linked = eqMgr.UpdateValuesFromExternalEquationFile
    On Error GoTo 0
    If eqMgr.LinkToFile And eqMgr.GetCount > 0 Then
        Note True, "equation file linked: " & eqMgr.GetCount & " equations / global variables from car_params.txt"
    Else
        Note False, "equation file NOT linked (plane offsets stay plain numbers): Tools > Equations > Link to external file"
    End If

    ' --- default planes renamed --------------------------------------------------------------
    Dim fGround As SldWorks.Feature, fCentre As SldWorks.Feature, fAxle As SldWorks.Feature
    Set fGround = defPlanes(1): Set fCentre = defPlanes(2): Set fAxle = defPlanes(3)
    RenameTo fGround, "GROUND"
    RenameTo fCentre, "CENTRE"
    RenameTo fAxle, "FRONT_AXLE"

    ' --- 3. planes --------------------------------------------------------------------------
    Dim fRear As SldWorks.Feature, fWheel As SldWorks.Feature
    Set fRear = OffsetPlane(fAxle, "REAR_AXLE", P("wheelbase"), 0, "wheelbase", eqMgr)
    OffsetPlane fAxle, "MAIN_HOOP", P("main_hoop_x"), 0, "main_hoop_x", eqMgr
    OffsetPlane fAxle, "FRONT_HOOP", P("front_hoop_x"), 0, "front_hoop_x", eqMgr
    Set fWheel = OffsetPlane(fGround, "WHEEL_CENTRE_HEIGHT", P("tyre_rolling_radius"), 2, "tyre_rolling_radius", eqMgr)

    ' --- 4. axes ----------------------------------------------------------------------------
    MakeAxis fAxle, fWheel, "FRONT_AXLE_AXIS"
    MakeAxis fRear, fWheel, "REAR_AXLE_AXIS"

    ' --- 5. hardpoints ----------------------------------------------------------------------
    HardpointSketch P, hpFront, "HP_front_right"
    HardpointSketch P, hpRear, "HP_rear_right"

    swModel.ClearSelection2 True
    swModel.ForceRebuild3 False
    swModel.ShowNamedView2 "*Isometric", 7
    swModel.ViewZoomtofit2

    ' --- 6. save + report ----------------------------------------------------------------
    Dim saved As Boolean, errs As Long, warns As Long
    If swModel.GetPathName = "" Then
        If Dir(savePath) <> "" Then
            Note False, "not saved: " & savePath & " already exists (save this part under another name by hand)"
        Else
            If Dir(repoRoot & "\cad\layout", vbDirectory) = "" Then MkDir repoRoot & "\cad\layout"
            saved = swModel.Extension.SaveAs3(savePath, swSaveAsVersion_e.swSaveAsCurrentVersion, _
                        swSaveAsOptions_e.swSaveAsOptions_Silent, Nothing, Nothing, errs, warns)
            Note saved, "saved as " & savePath & IIf(saved, "", " FAILED (error " & errs & ")")
        End If
    Else
        saved = swModel.Save3(swSaveAsOptions_e.swSaveAsOptions_Silent, errs, warns)
        Note saved, "saved " & swModel.GetPathName & IIf(saved, "", " FAILED (error " & errs & ")")
    End If

    Dim full As String
    full = IIf(allPass, "ALL PASS", "SOME STEPS FAILED") & "   (" & Format(Now, "yyyy-mm-dd hh:nn") & ")" & vbCrLf & vbCrLf & report & _
           vbCrLf & IIf(failures = "", "No failures.", "Failures:" & vbCrLf & failures)
    WriteReport reportFile, full
    Debug.Print full
    MsgBox Left$(full, 900) & IIf(Len(full) > 900, vbCrLf & "...", "") & vbCrLf & vbCrLf & "Full report: " & reportFile, _
           IIf(allPass, vbInformation, vbExclamation)
End Sub

' Offset plane from a base plane by value_mm, placed and checked by its real position.
' axisIdx: which coordinate the plane's origin moves along (0 = X, 1 = Y, 2 = Z).
Private Function OffsetPlane(ByVal baseF As SldWorks.Feature, ByVal nm As String, ByVal value_mm As Double, _
                             ByVal axisIdx As Long, ByVal globalName As String, ByVal eqMgr As SldWorks.EquationMgr) As SldWorks.Feature
    Dim f As SldWorks.Feature, pos As Double, attempt As Long, opt As Long
    For attempt = 1 To 2
        opt = swRefPlaneReferenceConstraints_e.swRefPlaneReferenceConstraint_Distance
        If (value_mm < 0) Xor (attempt = 2) Then opt = opt + swRefPlaneReferenceConstraints_e.swRefPlaneReferenceConstraint_OptionFlip
        swModel.ClearSelection2 True
        baseF.Select2 False, 0
        Set f = swModel.FeatureManager.InsertRefPlane(opt, Abs(value_mm) / 1000#, 0, 0#, 0, 0#)
        If f Is Nothing Then
            Note False, nm & ": InsertRefPlane refused"
            Exit Function
        End If
        pos = PlaneOrigin(f, axisIdx) * 1000#
        If Abs(pos - value_mm) < 0.01 Then Exit For
        If attempt = 1 Then
            ' wrong side: delete it and try the other direction
            swModel.ClearSelection2 True
            f.Select2 False, 0
            swModel.Extension.DeleteSelection2 swDeleteSelectionOptions_e.swDelete_Absorbed
        End If
    Next attempt
    RenameTo f, nm
    If Abs(pos - value_mm) >= 0.01 Then
        Note False, nm & ": lands at " & Format(pos, "0.0") & " mm, expected " & Format(value_mm, "0.0")
    Else
        Note True, nm & " at " & Format(value_mm, "0.0") & " mm" & TieToGlobal(eqMgr, nm, globalName, value_mm < 0)
    End If
    Set OffsetPlane = f
End Function

' Equation "D1@<plane>" = "<global>" (absolute value: the direction is in the plane feature).
Private Function TieToGlobal(ByVal eqMgr As SldWorks.EquationMgr, ByVal planeName As String, ByVal globalName As String, _
                             ByVal negative As Boolean) As String
    If Not eqMgr.LinkToFile Then
        TieToGlobal = " (value only, no equation file)"
        Exit Function
    End If
    Dim eq As String, idx As Long
    If negative Then
        eq = """D1@" & planeName & """ = -""" & globalName & """"
    Else
        eq = """D1@" & planeName & """ = """ & globalName & """"
    End If
    idx = eqMgr.Add3(-1, eq, True, swInConfigurationOpts_e.swAllConfiguration, Empty)
    If idx < 0 Then
        TieToGlobal = " (equation " & eq & " refused: value only)"
    Else
        TieToGlobal = " = """ & globalName & """"
    End If
End Function

Private Function PlaneOrigin(ByVal f As SldWorks.Feature, ByVal axisIdx As Long) As Double
    Dim rp As SldWorks.RefPlane, xf As SldWorks.MathTransform, d As Variant
    Set rp = f.GetSpecificFeature2
    If rp Is Nothing Then Exit Function
    Set xf = rp.Transform
    If xf Is Nothing Then Exit Function
    d = xf.ArrayData
    PlaneOrigin = d(9 + axisIdx)
End Function

Private Sub MakeAxis(ByVal f1 As SldWorks.Feature, ByVal f2 As SldWorks.Feature, ByVal nm As String)
    If f1 Is Nothing Or f2 Is Nothing Then
        Note False, nm & ": a plane is missing"
        Exit Sub
    End If
    swModel.ClearSelection2 True
    f1.Select2 False, 0
    f2.Select2 True, 0
    If Not swModel.InsertAxis2(True) Then
        Note False, nm & ": InsertAxis2 refused"
        Exit Sub
    End If
    Dim f As SldWorks.Feature
    Set f = swModel.Extension.GetLastFeatureAdded
    RenameTo f, nm
    Note True, nm
End Sub

' One 3D sketch with a point per hardpoint, then one named reference point each.
Private Sub HardpointSketch(ByVal P As Object, ByVal names As Collection, ByVal sketchName As String)
    Dim skMgr As SldWorks.SketchManager, pts() As SldWorks.SketchPoint, k As Long, nm As Variant
    Dim swSketch As SldWorks.Sketch, swFeat As SldWorks.Feature
    Set skMgr = swModel.SketchManager
    ReDim pts(1 To names.Count)
    swModel.ClearSelection2 True
    skMgr.AddToDB = True              ' exact coordinates, no snapping between points
    skMgr.Insert3DSketch True
    k = 0
    For Each nm In names
        k = k + 1
        Set pts(k) = skMgr.CreatePoint(P(nm & "_x") / 1000#, P(nm & "_y") / 1000#, P(nm & "_z") / 1000#)
    Next nm
    Set swSketch = skMgr.ActiveSketch
    On Error Resume Next
    If Not swSketch Is Nothing Then Set swFeat = swSketch
    On Error GoTo 0
    skMgr.Insert3DSketch True
    skMgr.AddToDB = False
    If swFeat Is Nothing Then Set swFeat = swModel.Extension.GetLastFeatureAdded
    RenameTo swFeat, sketchName

    Dim ret As Variant, f As SldWorks.Feature, made As Long, bad As String
    k = 0
    For Each nm In names
        k = k + 1
        Set f = Nothing
        swModel.ClearSelection2 True
        If Not pts(k) Is Nothing Then
            If pts(k).Select4(False, Nothing) Then
                ret = Empty
                On Error Resume Next
                ret = swModel.FeatureManager.InsertReferencePoint(swRefPointType_e.swRefPointSketchPoint, 0, 0#, 1)
                If IsArray(ret) Then
                    Set f = ret(0)
                ElseIf IsObject(ret) Then
                    Set f = ret
                End If
                On Error GoTo 0
            End If
        End If
        If f Is Nothing Then
            bad = bad & nm & " "
        Else
            RenameTo f, "HP_" & nm
            made = made + 1
        End If
    Next nm
    swModel.ClearSelection2 True
    Note (made = names.Count), sketchName & ": " & names.Count & " points, " & made & " named reference points HP_*" & _
         IIf(bad = "", "", " (no reference point for: " & bad & ")")
End Sub

' Names "f_lwb_in_fwd" etc. for which <name>_x, _y and _z all exist.
Private Function HardpointNames(ByVal P As Object, ByVal prefix As String) As Collection
    Dim c As New Collection, key As Variant, base As String
    For Each key In P.Keys
        If Left$(key, Len(prefix)) = prefix And Right$(key, 2) = "_x" Then
            base = Left$(key, Len(key) - 2)
            If P.Exists(base & "_y") And P.Exists(base & "_z") Then c.Add base
        End If
    Next key
    Set HardpointNames = c
End Function

' car_params.txt: "name"= number  ' comment. Lines whose value is an expression are skipped.
Private Function ReadParams(ByVal path As String) As Object
    Dim d As Object, lines As Variant, k As Long, ln As String, q2 As Long, nm As String, v As String, c As Long
    Set d = CreateObject("Scripting.Dictionary")
    lines = ReadTextLines(path)
    For k = 0 To UBound(lines)
        ln = Trim$(lines(k))
        If Left$(ln, 1) = """" Then
            q2 = InStr(2, ln, """")
            If q2 > 2 Then
                nm = Mid$(ln, 2, q2 - 2)
                v = Mid$(ln, q2 + 1)
                c = InStr(v, "'")
                If c > 0 Then v = Left$(v, c - 1)
                v = Trim$(Replace(v, "=", "", 1, 1))
                If v <> "" And IsNumeric(v) Then d(nm) = Val(v)
            End If
        End If
    Next k
    Set ReadParams = d
End Function

' The first n reference planes in the tree (the default Front, Top, Right).
Private Function FirstRefPlanes(ByVal m As SldWorks.ModelDoc2, ByVal n As Long) As Collection
    Dim c As New Collection, f As SldWorks.Feature
    Set f = m.FirstFeature
    Do While Not f Is Nothing And c.Count < n
        If f.GetTypeName2 = "RefPlane" Then c.Add f
        Set f = f.GetNextFeature
    Loop
    Set FirstRefPlanes = c
End Function

Private Sub RenameTo(ByVal f As SldWorks.Feature, ByVal nm As String)
    If f Is Nothing Then
        Note False, nm & ": no feature to rename"
        Exit Sub
    End If
    On Error Resume Next
    f.Name = nm
    On Error GoTo 0
    If f.Name <> nm Then Note False, nm & ": NOT renamed (is " & f.Name & ")"
End Sub

Private Sub Note(ByVal ok As Boolean, ByVal txt As String)
    report = report & IIf(ok, "PASS  ", "FAIL  ") & txt & vbCrLf
    If Not ok Then
        failures = failures & "- " & txt & vbCrLf
        allPass = False
    End If
End Sub

Private Function FindFeature(ByVal m As SldWorks.ModelDoc2, ByVal nm As String) As SldWorks.Feature
    Dim f As SldWorks.Feature
    Set f = m.FirstFeature
    Do While Not f Is Nothing
        If StrComp(f.Name, nm, vbTextCompare) = 0 Then
            Set FindFeature = f
            Exit Function
        End If
        Set f = f.GetNextFeature
    Loop
    Set FindFeature = Nothing
End Function

Private Sub WriteReport(ByVal path As String, ByVal txt As String)
    Dim fnum As Integer, folder As String
    folder = Left$(path, InStrRev(path, "\") - 1)
    If Dir(folder, vbDirectory) = "" Then MkDir folder
    fnum = FreeFile
    Open path For Output As #fnum
    Print #fnum, txt
    Close #fnum
End Sub

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
