Attribute VB_Name = "SaveStandardViews"
' ============================================================================
' SaveStandardViews.bas  (SolidWorks VBA macro module)
' STATUS: untested, needs the app.
' ----------------------------------------------------------------------------
' What it does
'   Saves PNG screenshots of the active document in six standard views
'   (isometric, front, right, top, rear, bottom) into media/views/ as
'   <docname>_<config>_<view>.png, white background, zoom to fit, shaded with
'   edges. One click gives the log a consistent set of pictures for every
'   session, and Ring 7 can reuse them for the README if RealView is enough.
'
' How to install: see ImportAirfoil.bas (New macro, then File > Import File).
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

    ' Plain white background, shaded with edges
    swApp.SetUserPreferenceToggle swUserPreferenceToggle_e.swColorsGradientPartBackground, False
    swModel.ViewDisplayShadedWithEdges

    Dim views As Variant, names As Variant, k As Long
    views = Array(swStandardViews_e.swIsometricView, swStandardViews_e.swFrontView, _
                  swStandardViews_e.swRightView, swStandardViews_e.swTopView, _
                  swStandardViews_e.swBackView, swStandardViews_e.swBottomView)
    names = Array("iso", "front", "right", "top", "rear", "bottom")

    Dim errs As Long, warns As Long, ok As Boolean
    For k = 0 To UBound(views)
        swModel.ShowNamedView2 "", views(k)
        swModel.ViewZoomtofit2
        swModel.GraphicsRedraw2
        Dim outFile As String
        outFile = outDir & "\" & docName & "_" & cfg & "_" & names(k) & ".png"
        ok = swModel.Extension.SaveAs3(outFile, swSaveAsVersion_e.swSaveAsCurrentVersion, _
                 swSaveAsOptions_e.swSaveAsOptions_Silent, Nothing, Nothing, errs, warns)
        If Not ok Then Debug.Print "Failed: " & outFile & " err=" & errs
    Next k
    swModel.ShowNamedView2 "", swStandardViews_e.swIsometricView
    swModel.ViewZoomtofit2
    MsgBox "Saved 6 views to " & outDir, vbInformation
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

Private Function RepoRootFromMacroPath() As String
    Dim p As String
    p = Application.SldWorks.GetCurrentMacroPathName
    If p = "" Then
        RepoRootFromMacroPath = CurDir$
    Else
        p = Left$(p, InStrRev(p, "\") - 1)
        p = Left$(p, InStrRev(p, "\") - 1)
        p = Left$(p, InStrRev(p, "\") - 1)
        RepoRootFromMacroPath = p
    End If
End Function
