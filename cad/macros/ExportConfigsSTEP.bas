Attribute VB_Name = "ExportConfigsSTEP"
' ============================================================================
' ExportConfigsSTEP.bas  (SolidWorks VBA macro module)
' STATUS: untested, needs the app (audited against the 2026 SP2.1 type library).
' ----------------------------------------------------------------------------
' What it does
'   For the active part or assembly, activates every configuration in turn,
'   rebuilds, and saves a STEP AP214 file to cfd/geometry/<docname>_<config>.STEP.
'   Also writes cfd/geometry/export_log.txt with the date, document, config,
'   rebuild errors and mass properties (mass in kg, CG in mm) per config,
'   which is the Ring 2 "mass and CG" check in one place.
'
' Intended use
'   * On the CFD half-car body part: configurations A, B, C, D -> four STEPs.
'   * On the full assembly for the v1.0.0 release STEP.
'
' How to install and run: see cad/macros/README.md (Tools > Macro > New,
'   File > Import File, then Tools > Macro > Run on the .swp, not the .bas).
'
' Repo root
'   Found by walking up from the folder of the running .swp until a folder
'   with params\car_params.txt is found. Save the .swp anywhere inside the
'   repo (cad\macros is the convention).
'
' Fixes after the 2026 test of the other macros
'   * swUserPreferenceIntegerValue_e.swStepExportGeometry is not in the 2026
'     type library (checked against SolidWorks.Interop.swconst.dll, 2026
'     SP2.1). A missing enum name is a compile error that On Error cannot
'     catch, so the line is removed; set Tools > Options > Export > STEP
'     output (solid/surface) once by hand. swStepAP (= 75) exists and stays.
'
' Notes
'   * STEP export units follow the document units (mm).
'   * Set Tools > Options > Export > STEP to "Solid/Surface geometry" and
'     AP214 once; the macro also sets the AP214 preference via the API.
'   * Ansys Student imports STEP directly (SpaceClaim / Fluent Meshing).
' ============================================================================
Option Explicit

Sub main()
    Dim swApp As SldWorks.SldWorks
    Dim swModel As SldWorks.ModelDoc2
    Set swApp = Application.SldWorks
    Set swModel = swApp.ActiveDoc
    If swModel Is Nothing Then
        MsgBox "Open a part or assembly first.", vbExclamation
        Exit Sub
    End If
    If swModel.GetType = swDocDRAWING Then
        MsgBox "Drawings cannot be exported to STEP with this macro.", vbExclamation
        Exit Sub
    End If

    Dim repoRoot As String
    repoRoot = RepoRootFromMacroPath()
    Dim outDir As String
    outDir = repoRoot & "\cfd\geometry"
    If Dir(outDir, vbDirectory) = "" Then MkDir outDir

    ' STEP AP214. Solid/surface output follows Tools > Options > Export > STEP.
    swApp.SetUserPreferenceIntegerValue swUserPreferenceIntegerValue_e.swStepAP, 214

    Dim docName As String
    docName = BaseNameOf(swModel.GetPathName)
    If docName = "" Then docName = "unsaved"

    Dim cfgNames As Variant
    cfgNames = swModel.GetConfigurationNames
    Dim startCfg As String
    startCfg = swModel.ConfigurationManager.ActiveConfiguration.Name

    Dim logPath As String
    logPath = outDir & "\export_log.txt"
    Dim fnum As Integer: fnum = FreeFile
    Open logPath For Append As #fnum
    Print #fnum, "---- " & Format(Now, "yyyy-mm-dd hh:nn") & "  " & swModel.GetPathName

    Dim i As Long, errs As Long, warns As Long
    For i = 0 To UBound(cfgNames)
        Dim cfg As String: cfg = cfgNames(i)
        swModel.ShowConfiguration2 cfg
        swModel.ForceRebuild3 False
        Dim outFile As String
        outFile = outDir & "\" & docName & "_" & SafeName(cfg) & ".STEP"
        Dim ok As Boolean
        ok = swModel.Extension.SaveAs3(outFile, swSaveAsVersion_e.swSaveAsCurrentVersion, _
                 swSaveAsOptions_e.swSaveAsOptions_Silent, Nothing, Nothing, errs, warns)
        ' Mass properties of this configuration (kg, m -> mm)
        Dim mp As SldWorks.MassProperty
        Set mp = swModel.Extension.CreateMassProperty
        Dim cg As Variant
        Dim massTxt As String
        If Not mp Is Nothing Then
            cg = mp.CenterOfMass
            massTxt = "mass_kg=" & Format(mp.Mass, "0.000") & _
                      " cg_mm=(" & Format(cg(0) * 1000, "0.0") & ", " & Format(cg(1) * 1000, "0.0") & ", " & Format(cg(2) * 1000, "0.0") & ")"
        Else
            massTxt = "mass: n/a"
        End If
        Print #fnum, cfg & vbTab & IIf(ok, "OK", "FAILED err=" & errs & " warn=" & warns) & vbTab & outFile & vbTab & massTxt
    Next i
    Close #fnum
    swModel.ShowConfiguration2 startCfg
    MsgBox "Exported " & (UBound(cfgNames) + 1) & " configuration(s) to " & outDir & vbCrLf & "Log: " & logPath, vbInformation
End Sub

Private Function SafeName(ByVal s As String) As String
    Dim bad As Variant, k As Long
    bad = Array("\", "/", ":", "*", "?", """", "<", ">", "|", " ")
    For k = 0 To UBound(bad)
        s = Replace(s, bad(k), "_")
    Next k
    SafeName = s
End Function

Private Function BaseNameOf(ByVal path As String) As String
    Dim s As String
    If path = "" Then BaseNameOf = "": Exit Function
    s = Mid$(path, InStrRev(path, "\") + 1)
    If InStrRev(s, ".") > 0 Then s = Left$(s, InStrRev(s, ".") - 1)
    BaseNameOf = s
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
