using System;
using System.Collections.Generic;
using System.Linq;

namespace WarehouseSystem;

public class Warehouse
{
    private readonly object _syncRoot = new();
    private readonly List<ProductQuantity> _inventory = new();

    private int _id;
    private WarehouseType _type;
    private double _capacity;
    private string _address = string.Empty;

    public Warehouse(int id, WarehouseType type, double capacity, string address)
    {
        Id = id;
        UpdateDetails(type, capacity, address);
    }

    public int Id
    {
        get => _id;
        private set
        {
            if (value <= 0)
            {
                throw new ArgumentOutOfRangeException(nameof(value), "Warehouse id must be positive.");
            }

            _id = value;
        }
    }

    public WarehouseType Type
    {
        get => _type;
        private set => _type = value;
    }

    public double Capacity
    {
        get => _capacity;
        private set
        {
            if (value <= 0)
            {
                throw new ArgumentOutOfRangeException(nameof(value), "Capacity must be positive.");
            }

            _capacity = value;
        }
    }

    public string Address
    {
        get => _address;
        private set
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                throw new ArgumentException("Address must be provided.", nameof(value));
            }

            _address = value;
        }
    }

    public double FreeVolume
    {
        get
        {
            lock (_syncRoot)
            {
                return GetFreeVolumeInternal();
            }
        }
    }

    public int ProductKindsCount
    {
        get
        {
            lock (_syncRoot)
            {
                return _inventory.Count;
            }
        }
    }

    public void UpdateDetails(WarehouseType type, double capacity, string address)
    {
        if (capacity <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(capacity), "Capacity must be positive.");
        }

        if (string.IsNullOrWhiteSpace(address))
        {
            throw new ArgumentException("Address must be provided.", nameof(address));
        }

        lock (_syncRoot)
        {
            var usedVolume = GetUsedVolumeInternal();
            if (capacity < usedVolume)
            {
                throw new InvalidOperationException("New capacity is smaller than the currently occupied volume.");
            }

            Type = type;
            Capacity = capacity;
            Address = address;
        }
    }

    public string GetDescription()
    {
        var free = FreeVolume;
        var used = Math.Round(Capacity - free, 2);
        return $"Склад {Id} | {Type} | Адрес: {Address} | Объем: {Capacity} | Свободно: {Math.Round(free, 2)} | Занято: {used} | Товаров: {ProductKindsCount}";
    }

    public bool AddProduct(Product product, int quantity)
    {
        if (product == null)
        {
            throw new ArgumentNullException(nameof(product));
        }

        if (product.IsDeleted)
        {
            throw new InvalidOperationException("Cannot add deleted product.");
        }

        if (quantity <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(quantity), "Quantity must be positive.");
        }

        lock (_syncRoot)
        {
            var incomingVolume = product.UnitVolume * quantity;
            if (incomingVolume > GetFreeVolumeInternal())
            {
                return false;
            }

            var existing = _inventory.FirstOrDefault(q => q.Product.Id == product.Id);
            if (existing == null)
            {
                _inventory.Add(new ProductQuantity(product, quantity));
            }
            else
            {
                existing.AddQuantity(quantity);
            }

            return true;
        }
    }

    public bool RemoveProduct(int productId, int quantity)
    {
        if (quantity <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(quantity), "Quantity must be positive.");
        }

        lock (_syncRoot)
        {
            var existing = _inventory.FirstOrDefault(q => q.Product.Id == productId);
            if (existing == null)
            {
                return false;
            }

            if (!existing.TryRemoveQuantity(quantity))
            {
                return false;
            }

            if (existing.Quantity == 0)
            {
                _inventory.Remove(existing);
            }

            return true;
        }
    }

    public decimal GetTotalCost()
    {
        lock (_syncRoot)
        {
            return _inventory.Sum(item => item.TotalCost);
        }
    }

    public Product? GetProductById(int productId)
    {
        lock (_syncRoot)
        {
            return _inventory.FirstOrDefault(x => x.Product.Id == productId)?.Product;
        }
    }

    public int GetQuantity(int productId)
    {
        lock (_syncRoot)
        {
            return _inventory.FirstOrDefault(x => x.Product.Id == productId)?.Quantity ?? 0;
        }
    }

    public IReadOnlyList<ProductQuantity> GetInventorySnapshot()
    {
        lock (_syncRoot)
        {
            return _inventory.Select(item => new ProductQuantity(item.Product, item.Quantity)).ToList();
        }
    }

    private double GetFreeVolumeInternal()
    {
        return Capacity - GetUsedVolumeInternal();
    }

    private double GetUsedVolumeInternal()
    {
        return _inventory.Sum(item => item.TotalVolume);
    }

    public static void OptimizeSortingWarehouses(IEnumerable<Warehouse> sortingWarehouses, IEnumerable<Warehouse> allWarehouses, Logger logger)
    {
        if (sortingWarehouses == null)
        {
            throw new ArgumentNullException(nameof(sortingWarehouses));
        }

        if (allWarehouses == null)
        {
            throw new ArgumentNullException(nameof(allWarehouses));
        }

        if (logger == null)
        {
            throw new ArgumentNullException(nameof(logger));
        }

        var generalWarehouses = allWarehouses.Where(w => w.Type == WarehouseType.General).ToList();
        var coldWarehouses = allWarehouses.Where(w => w.Type == WarehouseType.Cold).ToList();

        foreach (var sortingWarehouse in sortingWarehouses.Where(w => w.Type == WarehouseType.Sorting))
        {
            var inventorySnapshot = sortingWarehouse.GetInventorySnapshot();
            foreach (var item in inventorySnapshot)
            {
                var targetList = item.Product.ShelfLifeDays >= 30 ? generalWarehouses : coldWarehouses;
                var remaining = item.Quantity;

                foreach (var target in targetList)
                {
                    if (remaining <= 0)
                    {
                        break;
                    }

                    var movable = CalculateMovableQuantity(target, item.Product, remaining);
                    if (movable <= 0)
                    {
                        continue;
                    }

                    var moved = TransferProducts(sortingWarehouse, target, new List<int> { item.Product.Id }, new List<int> { movable }, logger);
                    if (moved)
                    {
                        remaining -= movable;
                    }
                }

                if (remaining > 0)
                {
                    logger.LogNote($"Не удалось полностью разгрузить сортировочный склад {sortingWarehouse.Id} для товара {item.Product.Name}. Осталось {remaining} шт.");
                }
            }
        }
    }

    public static void MoveExpiredProducts(IEnumerable<Warehouse> warehouses, Warehouse disposalWarehouse, Logger logger)
    {
        if (warehouses == null)
        {
            throw new ArgumentNullException(nameof(warehouses));
        }

        if (disposalWarehouse == null)
        {
            throw new ArgumentNullException(nameof(disposalWarehouse));
        }

        if (logger == null)
        {
            throw new ArgumentNullException(nameof(logger));
        }

        foreach (var warehouse in warehouses.Where(w => w.Id != disposalWarehouse.Id))
        {
            var inventorySnapshot = warehouse.GetInventorySnapshot();
            foreach (var item in inventorySnapshot.Where(i => i.Product.ShelfLifeDays <= 0))
            {
                var remaining = item.Quantity;
                while (remaining > 0)
                {
                    var movable = CalculateMovableQuantity(disposalWarehouse, item.Product, remaining);
                    if (movable <= 0)
                    {
                        logger.LogNote($"Недостаточно места на складе утилизации для {item.Product.Name}, осталось {remaining} шт. на складе {warehouse.Id}");
                        break;
                    }

                    var moved = TransferProducts(warehouse, disposalWarehouse, new List<int> { item.Product.Id }, new List<int> { movable }, logger);
                    if (!moved)
                    {
                        logger.LogNote($"Не удалось переместить {item.Product.Name} со склада {warehouse.Id} в утилизацию.");
                        break;
                    }

                    remaining -= movable;
                }
            }
        }
    }

    public static bool TransferProducts(Warehouse source, Warehouse destination, IList<int> productIds, IList<int> quantities, Logger logger)
    {
        if (source == null)
        {
            throw new ArgumentNullException(nameof(source));
        }

        if (destination == null)
        {
            throw new ArgumentNullException(nameof(destination));
        }

        if (productIds == null)
        {
            throw new ArgumentNullException(nameof(productIds));
        }

        if (quantities == null)
        {
            throw new ArgumentNullException(nameof(quantities));
        }

        if (logger == null)
        {
            throw new ArgumentNullException(nameof(logger));
        }

        if (productIds.Count == 0 || productIds.Count != quantities.Count)
        {
            throw new ArgumentException("Product ids and quantities must be non-empty and have the same length.");
        }

        var items = new List<(Product product, int quantity)>();
        for (var i = 0; i < productIds.Count; i++)
        {
            var quantity = quantities[i];
            if (quantity <= 0)
            {
                throw new ArgumentOutOfRangeException(nameof(quantities), "Quantities must be positive.");
            }

            var product = source.GetProductById(productIds[i]);
            if (product == null)
            {
                return false;
            }

            var available = source.GetQuantity(product.Id);
            if (available < quantity)
            {
                return false;
            }

            items.Add((product, quantity));
        }

        var totalVolume = items.Sum(x => x.product.UnitVolume * x.quantity);
        if (destination.FreeVolume < totalVolume)
        {
            return false;
        }

        var movedItems = new List<(Product product, int quantity)>();
        foreach (var (product, quantity) in items)
        {
            if (!source.RemoveProduct(product.Id, quantity))
            {
                Rollback(source, destination, movedItems);
                return false;
            }

            var added = destination.AddProduct(product, quantity);
            if (!added)
            {
                source.AddProduct(product, quantity);
                Rollback(source, destination, movedItems);
                return false;
            }

            movedItems.Add((product, quantity));
        }

        foreach (var (product, quantity) in movedItems)
        {
            logger.LogMovement(product, quantity, source, destination);
        }

        return true;
    }

    private static void Rollback(Warehouse source, Warehouse destination, IEnumerable<(Product product, int quantity)> movedItems)
    {
        foreach (var (product, quantity) in movedItems.Reverse())
        {
            destination.RemoveProduct(product.Id, quantity);
            source.AddProduct(product, quantity);
        }
    }

    private static int CalculateMovableQuantity(Warehouse target, Product product, int requestedQuantity)
    {
        var capacityForItem = (int)Math.Floor(target.FreeVolume / product.UnitVolume);
        return Math.Min(requestedQuantity, capacityForItem);
    }

    public static List<AnalysisResult> AnalyzeNetwork(IEnumerable<Warehouse> warehouses, Warehouse disposalWarehouse)
    {
        if (warehouses == null)
        {
            throw new ArgumentNullException(nameof(warehouses));
        }

        if (disposalWarehouse == null)
        {
            throw new ArgumentNullException(nameof(disposalWarehouse));
        }

        var results = new List<AnalysisResult>();
        foreach (var warehouse in warehouses)
        {
            var snapshot = warehouse.GetInventorySnapshot();
            var freeVolume = warehouse.FreeVolume;
            var usedVolume = warehouse.Capacity - freeVolume;
            var expired = snapshot.Any(item => item.Product.ShelfLifeDays <= 0);
            var unsuitableForType = snapshot.Any(item =>
                (warehouse.Type == WarehouseType.General && item.Product.ShelfLifeDays < 30)
                || (warehouse.Type == WarehouseType.Cold && item.Product.ShelfLifeDays >= 30)
                || (warehouse.Type == WarehouseType.Disposal && item.Product.ShelfLifeDays > 0));

            var needsSortingOptimization = warehouse.Type == WarehouseType.Sorting && snapshot.Any();

            var comments = new List<string>();
            if (freeVolume < 0)
            {
                comments.Add("Превышена ёмкость склада.");
            }

            if (expired)
            {
                comments.Add("Есть просроченная продукция.");
            }

            if (unsuitableForType)
            {
                comments.Add("Найдены товары, не подходящие по типу склада.");
            }

            if (warehouse.Type == WarehouseType.Sorting && needsSortingOptimization)
            {
                comments.Add("Необходимо перераспределение сортировочного склада.");
            }

            if (warehouse.Type == WarehouseType.Disposal && snapshot.Any(item => item.Product.ShelfLifeDays > 0))
            {
                comments.Add("На складе утилизации есть непросроченный товар.");
            }

            var result = new AnalysisResult
            {
                WarehouseId = warehouse.Id,
                Address = warehouse.Address,
                HasIssues = comments.Count > 0,
                NeedsSortingOptimization = needsSortingOptimization,
                NeedsExpiredRemoval = expired,
                NeedsTypeCorrection = unsuitableForType,
                Comment = string.Join(" ", comments),
                UsedVolume = usedVolume,
                FreeVolume = freeVolume
            };

            results.Add(result);
        }

        return results;
    }
}
