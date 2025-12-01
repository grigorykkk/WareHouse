using WarehouseSystem;
using WarehouseSystem.Api;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
        policy.AllowAnyOrigin()
            .AllowAnyHeader()
            .AllowAnyMethod());
});

builder.Services.AddSingleton<WarehouseState>();
builder.Services.AddEndpointsApiExplorer();

var app = builder.Build();

app.UseCors();

app.MapGet("/api/warehouses", (WarehouseState state) =>
{
    var items = state.Warehouses.Select(MapSummary).ToList();
    return Results.Ok(items);
});

app.MapGet("/api/warehouses/{id:int}", (int id, WarehouseState state) =>
{
    var warehouse = state.FindWarehouse(id);
    return warehouse == null
        ? Results.NotFound()
        : Results.Ok(MapDetail(warehouse));
});

app.MapGet("/api/warehouses/{id:int}/inventory", (int id, WarehouseState state) =>
{
    var warehouse = state.FindWarehouse(id);
    if (warehouse == null)
    {
        return Results.NotFound();
    }

    var inventory = warehouse.GetInventorySnapshot()
        .Select(MapInventoryItem)
        .ToList();

    return Results.Ok(inventory);
});

app.MapPost("/api/supplies", (SupplyRequest request, WarehouseState state) =>
{
    if (request?.Items == null || request.Items.Count == 0)
    {
        return Results.BadRequest("Supply must contain at least one item.");
    }

    var items = new List<ProductQuantity>();
    foreach (var item in request.Items)
    {
        if (item.Quantity <= 0)
        {
            return Results.BadRequest($"Quantity for product {item.ProductId} must be positive.");
        }

        try
        {
            var product = state.UpsertProduct(item.ProductId, item.SupplierId, item.Name, item.UnitVolume, item.UnitPrice, item.ShelfLifeDays);
            items.Add(new ProductQuantity(product, item.Quantity));
        }
        catch (Exception ex) when (ex is ArgumentException or ArgumentOutOfRangeException)
        {
            return Results.BadRequest(ex.Message);
        }
    }

    var supply = new Supply(items);
    var fullyPlaced = supply.Process(state.Warehouses, state.Logger);
    return Results.Ok(new SupplyResponse(fullyPlaced));
});

app.MapPost("/api/transfers", (TransferRequest request, WarehouseState state) =>
{
    if (request?.Items == null || request.Items.Count == 0)
    {
        return Results.BadRequest("No transfer items supplied.");
    }

    var source = state.FindWarehouse(request.SourceWarehouseId);
    if (source == null)
    {
        return Results.NotFound($"Warehouse {request.SourceWarehouseId} not found.");
    }

    var destination = state.FindWarehouse(request.DestinationWarehouseId);
    if (destination == null)
    {
        return Results.NotFound($"Warehouse {request.DestinationWarehouseId} not found.");
    }

    var productIds = new List<int>();
    var quantities = new List<int>();

    foreach (var item in request.Items)
    {
        if (item.Quantity <= 0)
        {
            return Results.BadRequest("Quantities must be positive.");
        }

        productIds.Add(item.ProductId);
        quantities.Add(item.Quantity);
    }

    bool moved;
    try
    {
        moved = Warehouse.TransferProducts(source, destination, productIds, quantities, state.Logger);
    }
    catch (Exception ex) when (ex is ArgumentException or ArgumentOutOfRangeException)
    {
        return Results.BadRequest(ex.Message);
    }

    if (!moved)
    {
        return Results.BadRequest("Transfer failed. Check product availability and destination capacity.");
    }

    return Results.Ok(new TransferResponse(true));
});

app.MapGet("/api/analysis", (WarehouseState state) =>
{
    var disposal = state.DisposalWarehouse;
    if (disposal == null)
    {
        return Results.Problem("Disposal warehouse is not configured.");
    }

    var analysis = Warehouse.AnalyzeNetwork(state.Warehouses, disposal)
        .Select(MapAnalysis)
        .ToList();

    return Results.Ok(analysis);
});

app.MapGet("/api/logs", (WarehouseState state) =>
{
    return Results.Ok(state.Logger.GetEntries());
});

app.Run();

static WarehouseSummaryDto MapSummary(Warehouse warehouse) => new(
    warehouse.Id,
    warehouse.Type.ToString(),
    warehouse.Address,
    warehouse.Capacity,
    warehouse.FreeVolume,
    Math.Round(warehouse.Capacity - warehouse.FreeVolume, 2),
    warehouse.ProductKindsCount
);

static WarehouseDetailDto MapDetail(Warehouse warehouse)
{
    var summary = MapSummary(warehouse);
    var inventory = warehouse.GetInventorySnapshot()
        .Select(MapInventoryItem)
        .ToList();

    return new WarehouseDetailDto(summary, inventory);
}

static InventoryItemDto MapInventoryItem(ProductQuantity item) => new(
    item.Product.Id,
    item.Product.Name,
    item.Quantity,
    item.Product.UnitVolume,
    item.TotalVolume,
    item.Product.UnitPrice,
    item.TotalCost,
    item.Product.ShelfLifeDays,
    item.Product.SupplierId
);

static AnalysisDto MapAnalysis(AnalysisResult result) => new(
    result.WarehouseId,
    result.Address,
    result.HasIssues,
    result.NeedsSortingOptimization,
    result.NeedsExpiredRemoval,
    result.NeedsTypeCorrection,
    result.UsedVolume,
    result.FreeVolume,
    result.Comment
);
