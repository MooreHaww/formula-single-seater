Attribute VB_Name = "BuildAssembly"
' ============================================================================
' BuildAssembly.bas  (SolidWorks VBA macro module)
' STATUS: untested, needs the app. Every call checked against the installed
'         2026 SP2.1 interop DLLs (exact interface per variable).
' ----------------------------------------------------------------------------
' What it does (one click, nothing needs to be open)
'   Builds or updates the top assembly cad\formula_single_seater.SLDASM from
'   what exists today: the master layout (BuildLayout), the chassis
'   (BuildTubes / TrimTubes) and the 18 build123d STEP bodies in cad\step.
'   Every part is modelled in car coordinates, so every part sits at the
'   assembly origin with no offset.
'   1. Checks first, changes nothing: master_layout.SLDPRT and chassis.SLDPRT
'      exist; lists which STEP bodies exist. Stops with "Nothing was changed"
'      if the layout or the chassis is missing.
'   2. Each cad\step\<name>.step without a cad\body\<name>.SLDPRT is imported
'      and saved there (once; later runs reuse the SLDPRT).
'   3. Opens cad\formula_single_seater.SLDASM if it exists (then only adds
'      what is missing), otherwise makes it from the default assembly template.
'   4. Layout first, fixed. Every other part: placed at the origin, then three
'      Coincident mates between its first three planes and the layout's
'      GROUND, CENTRE, FRONT_AXLE (named <component>_G/_C/_X). A part whose
'      mates are refused is fixed in place instead, and listed.
'   5. Left wheels: tyres and rims are built for the right corner; the left
'      ones are a second instance turned 180 deg about the vertical axis
'      through the axle (a rigid move, so no mirror file is needed; the rim's
'      40 mm disc offset stays outboard). Fixed.
'   6. Rebuild, Interference Detection (coincidence not counted, the
'      chassis' own tube-to-tube contacts not counted), Mass Properties.
'   7. Saves, final PASS/FAIL message, cad\build_assembly_report.txt.
'
' Not in this version (scriptable, but the parts do not exist yet): the
' suspension corner sub-assemblies with their joint mates, the wings as
' sub-assemblies, the A to D configurations. They follow 15_assembly.md once
' the wishbone, upright and hub parts are made.
'
' Depends on run-time behaviour (not provable from the type library)
'   * AddComponent5 needs the part loaded: the macro opens each part first.
'   * STEP import by LoadFile4 uses the import options last set in the app.
'   * Component2.Transform2 set to identity puts the part origin on the
'     assembly origin; the plane mates then hold without moving anything.
'   * Which three planes a part has first in its tree (the template's Front,
'     Top, Right); for parts made from the same template they match the layout.
'   * Mate2 renamed through a Feature cast.
' ============================================================================
Option Explicit

Private swApp As SldWorks.SldWorks
Private swAsmModel As SldWorks.ModelDoc2
Private swAsm As SldWorks.AssemblyDoc
Private report As String
Private failures As String
Private allPass As Boolean
Private layoutComp As SldWorks.Component2

Sub main()
    Set swApp = Application.SldWorks
    report = "": failures = "": allPass = True

    ' --- 1. checks -------------------------------------------------------------------
    Dim repoRoot As String, layoutPath As String, chassisPath As String, asmPath As String, reportFile As String
    repoRoot = RepoRootFromMacroPath()
    layoutPath = repoRoot & "\cad\layout\master_layout.SLDPRT"
    chassisPath = repoRoot & "\cad\chassis\chassis.SLDPRT"
    asmPath = repoRoot & "\cad\formula_single_seater.SLDASM"
    reportFile = repoRoot & "\cad\build_assembly_report.txt"
    If Dir(layoutPath) = "" Or Dir(chassisPath) = "" Then
        MsgBox "Missing " & IIf(Dir(layoutPath) = "", layoutPath & " (run BuildLayout) ", "") & _
               IIf(Dir(chassisPath) = "", chassisPath & " (run BuildTubes)", "") & vbCrLf & "Nothing was changed.", vbExclamation
        Exit Sub
    End If
    Dim P As Object, wheelbase As Double
    Set P = ReadParams(repoRoot & "\params\car_params.txt")
    If P.Exists("wheelbase") Then wheelbase = P("wheelbase") Else wheelbase = 1550
    Dim stepNames As Collection, s As String
    Set stepNames = New Collection
    s = Dir(repoRoot & "\cad\step\*.step")
    Do While s <> ""
        stepNames.Add Left$(s, Len(s) - 5)
        s = Dir()
    Loop

    ' --- 2. STEP -> SLDPRT ---------------------------------------------------------------------
    Dim nm As Variant, partPath As String, parts As Collection
    Set parts = New Collection
    parts.Add chassisPath
    For Each nm In stepNames
        partPath = repoRoot & "\cad\body\" & nm & ".SLDPRT"
        If Dir(partPath) = "" Then ImportStep repoRoot & "\cad\step\" & nm & ".step", partPath
        If Dir(partPath) <> "" Then parts.Add partPath
    Next nm

    ' --- 3. the assembly -----------------------------------------------------------------------
    Dim errs As Long, warns As Long, isNew As Boolean
    If Dir(asmPath) <> "" Then
        Set swAsmModel = swApp.OpenDoc6(asmPath, swDocumentTypes_e.swDocASSEMBLY, swOpenDocOptions_e.swOpenDocOptions_Silent, "", errs, warns)
        If swAsmModel Is Nothing Then
            MsgBox "Could not open " & asmPath & " (error " & errs & "). Nothing was changed.", vbExclamation
            Exit Sub
        End If
    Else
        Dim tmpl As String
        tmpl = swApp.GetUserPreferenceStringValue(swUserPreferenceStringValue_e.swDefaultTemplateAssembly)
        Set swAsmModel = swApp.NewDocument(tmpl, 0, 0#, 0#)
        If swAsmModel Is Nothing Then
            MsgBox "No assembly could be made from the default template (" & tmpl & "). Nothing was changed.", vbExclamation
            Exit Sub
        End If
        isNew = True
    End If
    Set swAsm = swAsmModel
    Dim present As Object
    Set present = ComponentsByPath()

    ' --- 4. layout, fixed, then the parts --------------------------------------------------------
    If present.Exists(LCase$(layoutPath)) Then
        Set layoutComp = present(LCase$(layoutPath))
        Note True, "master_layout: already in the assembly"
    Else
        Set layoutComp = AddAt(layoutPath, Identity())
        If layoutComp Is Nothing Then
            Note False, "master_layout: AddComponent5 refused, nothing else can be mated"
        Else
            FixIt layoutComp
            Note layoutComp.IsFixed, "master_layout: inserted, " & IIf(layoutComp.IsFixed, "fixed", "NOT fixed")
        End If
    End If

    Dim c As SldWorks.Component2, nMated As Long, nFixed As Long, nKept As Long
    For Each nm In parts
        If present.Exists(LCase$(nm)) Then
            nKept = nKept + 1
        Else
            Set c = AddAt(CStr(nm), Identity())
            If c Is Nothing Then
                Note False, FileTitle(CStr(nm)) & ": AddComponent5 refused"
            ElseIf MateToLayout(c) Then
                nMated = nMated + 1
            Else
                FixIt c
                nFixed = nFixed + 1
                Note c.IsFixed, FileTitle(CStr(nm)) & ": plane mates refused, fixed in place instead"
            End If
        End If
    Next nm
    Note True, "parts: " & nMated & " mated to GROUND/CENTRE/FRONT_AXLE, " & nFixed & " fixed instead, " & nKept & " already there"

    ' --- 5. left wheels ---------------------------------------------------------------------------
    Dim wheel As Variant, xAxle As Double, wp As String, nLeft As Long
    For Each wheel In Array("tyre_front", "rim_front", "tyre_rear", "rim_rear")
        wp = repoRoot & "\cad\body\" & wheel & ".SLDPRT"
        If Dir(wp) <> "" Then
            If CountInstances(wp) < 2 Then
                xAxle = 0#
                If Right$(wheel, 4) = "rear" Then xAxle = wheelbase / 1000#
                Set c = AddAt(wp, TurnedAboutZ(xAxle))
                If c Is Nothing Then
                    Note False, wheel & " left: AddComponent5 refused"
                Else
                    FixIt c
                    nLeft = nLeft + 1
                End If
            End If
        End If
    Next wheel
    If nLeft > 0 Then Note True, "left wheels: " & nLeft & " instances turned 180 deg about the axle's vertical axis, fixed"

    swAsmModel.ClearSelection2 True
    swAsmModel.ForceRebuild3 False
    swAsmModel.ShowNamedView2 "*Isometric", 7
    swAsmModel.ViewZoomtofit2

    ' --- 6. checks: interference, mass -----------------------------------------------------------
    Dim idm As SldWorks.InterferenceDetectionMgr, ints As Variant, k As Long, j As Long
    Dim itf As SldWorks.Interference, comps As Variant, pair As String, intList As String, nInt As Long
    Set idm = swAsm.InterferenceDetectionManager
    If idm Is Nothing Then
        Note False, "interference detection: manager not available"
    Else
        idm.TreatCoincidenceAsInterference = False
        idm.IncludeMultibodyPartInterferences = False
        ints = idm.GetInterferences
        If IsArray(ints) Then
            For k = 0 To UBound(ints)
                Set itf = ints(k)
                comps = itf.Components
                pair = ""
                If IsArray(comps) Then
                    For j = 0 To UBound(comps)
                        pair = pair & IIf(j > 0, " / ", "") & comps(j).Name2
                    Next j
                End If
                intList = intList & "    " & pair & ": " & Format(itf.Volume * 1000000000#, "0") & " mm3" & vbCrLf
                nInt = nInt + 1
            Next k
        End If
        idm.Done
        Note (nInt = 0), "interference: " & nInt & " pair(s)" & IIf(nInt = 0, "", " (each is a fault unless it is a designed contact)")
        If intList <> "" Then report = report & intList
    End If
    Dim mp As SldWorks.MassProperty, cg As Variant
    Set mp = swAsmModel.Extension.CreateMassProperty
    If Not mp Is Nothing Then
        cg = mp.CenterOfMass
        report = report & "INFO  mass of what is in the assembly: " & Format(mp.Mass, "0.0") & " kg, CG x " & _
                 Format(cg(0) * 1000, "0") & " / y " & Format(cg(1) * 1000, "0") & " / z " & Format(cg(2) * 1000, "0") & _
                 " mm (partial car: no driver, battery, motor or suspension yet)" & vbCrLf
    End If

    ' --- 7. save + report -------------------------------------------------------------------------
    Dim saved As Boolean
    If isNew Then
        saved = swAsmModel.Extension.SaveAs3(asmPath, swSaveAsVersion_e.swSaveAsCurrentVersion, _
                    swSaveAsOptions_e.swSaveAsOptions_Silent, Nothing, Nothing, errs, warns)
    Else
        saved = swAsmModel.Save3(swSaveAsOptions_e.swSaveAsOptions_Silent, errs, warns)
    End If
    Note saved, IIf(saved, "saved " & asmPath, "NOT saved (error " & errs & ")")

    Dim full As String
    full = IIf(allPass, "ALL PASS", "SOME CHECKS FAILED") & "   (" & Format(Now, "yyyy-mm-dd hh:nn") & ")" & vbCrLf & vbCrLf & report & _
           vbCrLf & IIf(failures = "", "No failures.", "Failures:" & vbCrLf & failures)
    WriteReport reportFile, full
    Debug.Print full
    MsgBox Left$(full, 900) & IIf(Len(full) > 900, vbCrLf & "...", "") & vbCrLf & vbCrLf & "Full report: " & reportFile, _
           IIf(allPass, vbInformation, vbExclamation)
End Sub

' Import one STEP file and save it as a part.
Private Sub ImportStep(ByVal stepPath As String, ByVal partPath As String)
    Dim m As SldWorks.ModelDoc2, errs As Long, warns As Long, ok As Boolean, folder As String
    folder = Left$(partPath, InStrRev(partPath, "\") - 1)
    If Dir(folder, vbDirectory) = "" Then MkDir folder
    Set m = swApp.LoadFile4(stepPath, "r", Nothing, errs)
    If m Is Nothing Then
        Note False, FileTitle(stepPath) & ": STEP import refused (error " & errs & ")"
        Exit Sub
    End If
    ok = m.Extension.SaveAs3(partPath, swSaveAsVersion_e.swSaveAsCurrentVersion, swSaveAsOptions_e.swSaveAsOptions_Silent, _
                             Nothing, Nothing, errs, warns)
    Note ok, FileTitle(stepPath) & ": imported" & IIf(ok, " and saved as cad\body\" & FileTitle(partPath), ", NOT saved (error " & errs & ")")
    swApp.CloseDoc m.GetTitle
End Sub

' Open the part (AddComponent5 needs it loaded), go back to the assembly, add it, place it.
Private Function AddAt(ByVal path As String, ByVal xf As SldWorks.MathTransform) As SldWorks.Component2
    Dim m As SldWorks.ModelDoc2, errs As Long, warns As Long, c As SldWorks.Component2
    Set m = swApp.OpenDoc6(path, swDocumentTypes_e.swDocPART, swOpenDocOptions_e.swOpenDocOptions_Silent, "", errs, warns)
    swApp.ActivateDoc3 swAsmModel.GetTitle, False, swRebuildOnActivation_e.swDontRebuildActiveDoc, errs
    If m Is Nothing Then Exit Function
    Set c = swAsm.AddComponent5(path, swAddComponentConfigOptions_e.swAddComponentConfigOptions_CurrentSelectedConfig, _
                                "", False, "", 0#, 0#, 0#)
    If c Is Nothing Then Exit Function
    If Not xf Is Nothing Then c.Transform2 = xf
    Set AddAt = c
End Function

' Three coincident mates: the part's first three planes to GROUND, CENTRE, FRONT_AXLE.
Private Function MateToLayout(ByVal c As SldWorks.Component2) As Boolean
    If layoutComp Is Nothing Then Exit Function
    Dim m As SldWorks.ModelDoc2, f As SldWorks.Feature, names As New Collection
    Set m = c.GetModelDoc2
    If m Is Nothing Then Exit Function
    Set f = m.FirstFeature
    Do While Not f Is Nothing And names.Count < 3
        If f.GetTypeName2 = "RefPlane" Then names.Add f.Name
        Set f = f.GetNextFeature
    Loop
    If names.Count < 3 Then Exit Function
    Dim targets As Variant, tags As Variant, k As Long, ok As Boolean
    targets = Array("GROUND", "CENTRE", "FRONT_AXLE")
    tags = Array("_G", "_C", "_X")
    ok = True
    For k = 0 To 2
        If Not MatePlanes(layoutComp.FeatureByName(targets(k)), c.FeatureByName(names(k + 1)), c.Name2 & tags(k)) Then ok = False
    Next k
    MateToLayout = ok
End Function

Private Function MatePlanes(ByVal f1 As SldWorks.Feature, ByVal f2 As SldWorks.Feature, ByVal mateName As String) As Boolean
    If f1 Is Nothing Or f2 Is Nothing Then Exit Function
    Dim mt As SldWorks.Mate2, errStat As Long, align As Variant, mf As SldWorks.Feature
    For Each align In Array(swMateAlign_e.swMateAlignALIGNED, swMateAlign_e.swMateAlignCLOSEST)
        swAsmModel.ClearSelection2 True
        f1.Select2 False, 1
        f2.Select2 True, 1
        Set mt = swAsm.AddMate5(swMateType_e.swMateCOINCIDENT, align, False, 0#, 0#, 0#, 0#, 0#, 0#, 0#, 0#, False, False, 0, errStat)
        If Not mt Is Nothing Then Exit For
    Next align
    swAsmModel.ClearSelection2 True
    If mt Is Nothing Then Exit Function
    On Error Resume Next
    Set mf = mt
    If Not mf Is Nothing Then mf.Name = mateName
    On Error GoTo 0
    MatePlanes = True
End Function

Private Sub FixIt(ByVal c As SldWorks.Component2)
    swAsmModel.ClearSelection2 True
    If c.Select4(False, Nothing, False) Then
        swAsm.FixComponent
    End If
    swAsmModel.ClearSelection2 True
End Sub

Private Function Identity() As SldWorks.MathTransform
    Dim mu As SldWorks.MathUtility, d(15) As Double, v As Variant
    Set mu = swApp.GetMathUtility
    d(0) = 1: d(4) = 1: d(8) = 1: d(12) = 1
    v = d
    Set Identity = mu.CreateTransform(v)
End Function

' 180 deg about the vertical (Z) axis through (xAxle, 0): (x, y, z) -> (2 xAxle - x, -y, z). Metres.
Private Function TurnedAboutZ(ByVal xAxle As Double) As SldWorks.MathTransform
    Dim mu As SldWorks.MathUtility, d(15) As Double, v As Variant
    Set mu = swApp.GetMathUtility
    d(0) = -1: d(4) = -1: d(8) = 1: d(9) = 2 * xAxle: d(12) = 1
    v = d
    Set TurnedAboutZ = mu.CreateTransform(v)
End Function

' Top-level components by lower-case path (first instance).
Private Function ComponentsByPath() As Object
    Dim d As Object, comps As Variant, k As Long, c As SldWorks.Component2
    Set d = CreateObject("Scripting.Dictionary")
    comps = swAsm.GetComponents(True)
    If IsArray(comps) Then
        For k = 0 To UBound(comps)
            Set c = comps(k)
            If Not d.Exists(LCase$(c.GetPathName)) Then Set d(LCase$(c.GetPathName)) = c
        Next k
    End If
    Set ComponentsByPath = d
End Function

Private Function CountInstances(ByVal path As String) As Long
    Dim comps As Variant, k As Long, c As SldWorks.Component2
    comps = swAsm.GetComponents(True)
    If IsArray(comps) Then
        For k = 0 To UBound(comps)
            Set c = comps(k)
            If LCase$(c.GetPathName) = LCase$(path) Then CountInstances = CountInstances + 1
        Next k
    End If
End Function

Private Function FileTitle(ByVal path As String) As String
    FileTitle = Mid$(path, InStrRev(path, "\") + 1)
End Function

Private Sub Note(ByVal ok As Boolean, ByVal txt As String)
    report = report & IIf(ok, "PASS  ", "FAIL  ") & txt & vbCrLf
    If Not ok Then
        failures = failures & "- " & txt & vbCrLf
        allPass = False
    End If
End Sub

' car_params.txt: "name"= number  ' comment. Lines whose value is an expression are skipped.
Private Function ReadParams(ByVal path As String) As Object
    Dim d As Object, lines As Variant, k As Long, ln As String, q2 As Long, nm As String, v As String, c As Long
    Set d = CreateObject("Scripting.Dictionary")
    If Dir(path) = "" Then
        Set ReadParams = d
        Exit Function
    End If
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
