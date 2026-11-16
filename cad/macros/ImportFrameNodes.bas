Attribute VB_Name = "ImportFrameNodes"
' ============================================================================
' ImportFrameNodes.bas  (SolidWorks VBA macro module)
' STATUS: untested, needs the app.
' ----------------------------------------------------------------------------
' What it does
'   Reads cad/frame/frame_nodes.csv (node,x_mm,y_mm,z_mm,note) and
'   cad/frame/frame_tubes.csv (tube,node_a,node_b,group,od_mm,wall_mm,...)
'   and draws one 3D-sketch line per tube between the node coordinates in a
'   new 3D sketch of the active part. Afterwards:
'     1. Tools > Sketch Tools > Repair Sketch (merges endpoints that the API
'        left as separate coincident points; verify it is needed)
'     2. Rename the sketch FRAME_SKELETON
'     3. Insert > Weldments > Structural Member on the lines, group by group
'        (see docs/cad_playbook/02_chassis.md)
'   The lines carry no equations: regenerate the CSVs from MATLAB
'   (frame_layout.m) and rerun this macro when the hardpoints change.
'
' How to install: see ImportAirfoil.bas (New macro, then File > Import File).
' ============================================================================
Option Explicit

Sub main()
    Dim swApp As SldWorks.SldWorks
    Dim swModel As SldWorks.ModelDoc2
    Set swApp = Application.SldWorks
    Set swModel = swApp.ActiveDoc
    If swModel Is Nothing Then
        MsgBox "Open the part that should receive the frame skeleton.", vbExclamation
        Exit Sub
    End If
    If swModel.GetType <> swDocPART Then
        MsgBox "The active document must be a part.", vbExclamation
        Exit Sub
    End If

    Dim repoRoot As String
    repoRoot = RepoRootFromMacroPath()
    Dim nodesFile As String, tubesFile As String
    nodesFile = repoRoot & "\cad\frame\frame_nodes.csv"
    tubesFile = repoRoot & "\cad\frame\frame_tubes.csv"
    If Dir(nodesFile) = "" Or Dir(tubesFile) = "" Then
        MsgBox "Run matlab/cad/frame_layout.m first; expected " & nodesFile & " and " & tubesFile, vbExclamation
        Exit Sub
    End If

    ' --- nodes into a dictionary name -> (x, y, z) in metres ----------------------
    Dim nodes As Object
    Set nodes = CreateObject("Scripting.Dictionary")
    Dim fnum As Integer, line As String, parts() As String
    fnum = FreeFile
    Open nodesFile For Input As #fnum
    Line Input #fnum, line                                  ' header
    Do While Not EOF(fnum)
        Line Input #fnum, line
        If Left$(line, 1) <> "#" And Trim$(line) <> "" Then
            parts = Split(line, ",")
            If UBound(parts) >= 3 Then
                nodes(Trim$(parts(0))) = Array(CDbl(parts(1)) / 1000#, CDbl(parts(2)) / 1000#, CDbl(parts(3)) / 1000#)
            End If
        End If
    Loop
    Close #fnum

    ' --- lines ---------------------------------------------------------------------
    Dim skMgr As SldWorks.SketchManager
    Set skMgr = swModel.SketchManager
    skMgr.AddToDB = False          ' keep inference on so coincident endpoints merge (verify; set True if it is too slow)
    skMgr.DisplayWhenAdded = False
    skMgr.Insert3DSketch True
    Dim count As Long, missing As Long
    fnum = FreeFile
    Open tubesFile For Input As #fnum
    Line Input #fnum, line
    Do While Not EOF(fnum)
        Line Input #fnum, line
        If Left$(line, 1) <> "#" And Trim$(line) <> "" Then
            parts = Split(line, ",")
            If UBound(parts) >= 2 Then
                Dim a As String, b As String
                a = Trim$(parts(1)): b = Trim$(parts(2))
                If nodes.Exists(a) And nodes.Exists(b) Then
                    Dim pa As Variant, pb As Variant
                    pa = nodes(a): pb = nodes(b)
                    skMgr.CreateLine pa(0), pa(1), pa(2), pb(0), pb(1), pb(2)
                    count = count + 1
                Else
                    missing = missing + 1
                End If
            End If
        End If
    Loop
    Close #fnum
    skMgr.Insert3DSketch True      ' exit the sketch
    skMgr.DisplayWhenAdded = True
    skMgr.AddToDB = False

    ' rename the sketch
    Dim feat As SldWorks.Feature
    Set feat = swModel.FeatureManager.FeatureByPositionReverse(0)
    If Not feat Is Nothing Then feat.Name = "FRAME_SKELETON"
    swModel.ViewZoomtofit2
    MsgBox count & " tube lines drawn into FRAME_SKELETON (" & missing & " skipped for missing nodes)." & vbCrLf & _
           "Now run Tools > Sketch Tools > Repair Sketch, then add Structural Members.", vbInformation
End Sub

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
