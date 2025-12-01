namespace WarehouseSystem;

public class AnalysisResult
{
    public int WarehouseId { get; set; }

    public string? Address { get; set; }

    public bool HasIssues { get; set; }

    public bool NeedsSortingOptimization { get; set; }

    public bool NeedsExpiredRemoval { get; set; }

    public bool NeedsTypeCorrection { get; set; }

    public double UsedVolume { get; set; }

    public double FreeVolume { get; set; }

    public string? Comment { get; set; }
}
