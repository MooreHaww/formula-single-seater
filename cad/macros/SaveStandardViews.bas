Attribute VB_Name = "SaveStandardViews"
' ============================================================================
' SaveStandardViews.bas  (SolidWorks VBA macro module)
' STATUS: first version ran in SolidWorks 2026 SP2.1 Student after two lines
'         were commented out; this fixed version is untested, needs the app.
' ----------------------------------------------------------------------------
' What it does
'   Saves PNG screenshots of the active document in six standard views
'   (isometric, front, right, top, rear, bottom) into media/views/ as
'   <docname>_<config>_<view>.png, white background, zoom to fit, shaded with
'   edges. One click gives the log a consistent set of pictures for every
'   session, and Ring 7 can reuse them for the README if RealView is enough.
'
' Repo root
'   Found by walking up from the folder of the running .swp until a folder
'   with params\car_params.txt is found. Save the .swp anywhere inside the
'   repo (cad\macros is the convention). Outside the repo it falls back to
'   the current directory.
'
' How to install and run: see cad/macros/README.md (Tools > Macro > New,
'   File > Import File, then Tools > Macro > Run on the .swp, not the .bas).
'
' 2026 API notes (names and values checked against SolidWorks.Interop.swconst.dll
' of the installed 2026 SP2.1)
'   * ModelDoc2.ViewDisplayShadedWithEdges does not exist (runtime error 438).
'     Use ModelView.DisplayMode = swViewDisplayMode_ShadedWithEdges (= 5).
'   * swColorsBackgroundAppearance_PlainWhite does not exist (compile error).
'     The 2026 enum is swColorsBackgroundAppearance_e: Plain = 0, Gradient = 1,
'     Image = 2, DocumentScene = 3. "Plain" uses the viewport background
'     colour swSystemColorsViewportBackground (= 99), set here to white.
'   * The three background options are system options; the macro saves them
'     first and restores them at the end.
'
' Notes
'   * Image size follows the graphics window; maximise SolidWorks first.
'   * For the Ring 7 renders use SOLIDWORKS Visualize if installed; this macro
'     is for the daily log, not for the hero shot.
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

    Dim repoRoot As String
    repoRoot = RepoRootFromMacroPath()
    Dim outDir As String
    outDir = repoRoot & "\media\views"
    If Dir(repoRoot & "\media", vbDirectory) = "" Then MkDir repoRoot & "\media"
    If Dir(outDir, vbDirectory) = "" Then MkDir outDir

    Dim docName As String
    docName = BaseNameOf(swModel.GetPathName)
    If docName = "" Then docName = "unsaved"
    Dim cfg As String
    cfg = SafeName(swModel.ConfigurationManager.ActiveConfiguration.Name)

    ' --- plain white background (save the user's settings to restore later) ----
    Dim oldAppearance As Long, oldColour As Long, oldGradient As Boolean
    oldAppearance = swApp.GetUserPreferenceIntegerValue(swUserPreferenceIntegerValue_e.swColorsBackgroundAppearance)
    oldColour = swApp.GetUserPreferenceIntegerValue(swUserPreferenceIntegerValue_e.swSystemColorsViewportBackground)
    oldGradient = swApp.GetUserPreferenceToggle(swUserPreferenceToggle_e.swColorsGradientPartBackground)
    swApp.SetUserPreferenceIntegerValue swUserPreferenceIntegerValue_e.swColorsBackgroundAppearance, _
        swColorsBackgroundAppearance_e.swColorsBackgroundAppearance_Plain
    swApp.SetUserPreferenceIntegerValue swUserPreferenceIntegerValue_e.swSystemColorsViewportBackground, RGB(255, 255, 255)
    swApp.SetUserPreferenceToggle swUserPreferenceToggle_e.swColorsGradientPartBackground, False

    ' --- shaded with edges through the active ModelView ------------------------
    Dim swView As SldWorks.ModelView
    Set swView = swModel.ActiveView
    If Not swView Is Nothing Then
        swView.DisplayMode = swViewDisplayMode_e.swViewDisplayMode_ShadedWithEdges
    End If

    Dim views As Variant, names As Variant, k As Long
    views = Array(swStandardViews_e.swIsometricView, swStandardViews_e.swFrontView, _
                  swStandardViews_e.swRightView, swStandardViews_e.swTopView, _
                  swStandardViews_e.swBackView, swStandardViews_e.swBottomView)
    names = Array("iso", "front", "right", "top", "rear", "bottom")

    Dim errs As Long, warns As Long, ok As Boolean, nOk As Long
    For k = 0 To UBound(views)
        swModel.ShowNamedView2 "", views(k)
        swModel.ViewZoomtofit2
        swModel.GraphicsRedraw2
        Dim outFile As String
        outFile = outDir & "\" & docName & "_" & cfg & "_" & names(k) & ".png"
        ok = swModel.Extension.SaveAs3(outFile, swSaveAsVersion_e.swSaveAsCurrentVersion, _
                 swSaveAsOptions_e.swSaveAsOptions_Silent, Nothing, Nothing, errs, warns)
        If ok Then nOk = nOk + 1 Else Debug.Print "Failed: " & outFile & " err=" & errs
    Next k
    swModel.ShowNamedView2 "", swStandardViews_e.swIsometricView
    swModel.ViewZoomtofit2

    ' --- restore the user's background settings --------------------------------
    swApp.SetUserPreferenceIntegerValue swUserPreferenceIntegerValue_e.swColorsBackgroundAppearance, oldAppearance
    swApp.SetUserPreferenceIntegerValue swUserPreferenceIntegerValue_e.swSystemColorsViewportBackground, oldColour
    swApp.SetUserPreferenceToggle swUserPreferenceToggle_e.swColorsGradientPartBackground, oldGradient
    swModel.GraphicsRedraw2

    MsgBox "Saved " & nOk & " of 6 views to " & outDir, vbInformation
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
