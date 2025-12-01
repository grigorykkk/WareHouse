using System.Collections.Generic;

namespace WarehouseSystem.Api;

public record WarehouseSummaryDto(
    int Id,
    string Type,
    string Address,
    double Capacity,
    double FreeVolume,
    double UsedVolume,
    int ProductKindsCount);

public record InventoryItemDto(
    int ProductId,
    string Name,
    int Quantity,
    double UnitVolume,
    double TotalVolume,
    decimal UnitPrice,
    decimal TotalCost,
    int ShelfLifeDays,
    int SupplierId);

public record WarehouseDetailDto(WarehouseSummaryDto Warehouse, IReadOnlyCollection<InventoryItemDto> Inventory);

public class SupplyItemDto
{
    public int ProductId { get; set; }

    public int SupplierId { get; set; }

    public string Name { get; set; } = string.Empty;

    public double UnitVolume { get; set; }

    public decimal UnitPrice { get; set; }

    public int ShelfLifeDays { get; set; }

    public int Quantity { get; set; }
}

public class SupplyRequest
{
    public List<SupplyItemDto> Items { get; set; } = new();
}

public record SupplyResponse(bool FullyPlaced);

public class TransferItemDto
{
    public int ProductId { get; set; }

    public int Quantity { get; set; }
}

public class TransferRequest
{
    public int SourceWarehouseId { get; set; }

    public int DestinationWarehouseId { get; set; }

    public List<TransferItemDto> Items { get; set; } = new();
}

public record TransferResponse(bool Moved);

public record AnalysisDto(
    int WarehouseId,
    string? Address,
    bool HasIssues,
    bool NeedsSortingOptimization,
    bool NeedsExpiredRemoval,
    bool NeedsTypeCorrection,
    double UsedVolume,
    double FreeVolume,
    string? Comment);
