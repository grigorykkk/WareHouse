using System.Collections.Generic;
using System.Linq;

namespace WarehouseSystem;

public class WarehouseState
{
    private readonly List<Warehouse> _warehouses;
    private readonly Dictionary<int, Product> _products = new();
    private readonly object _syncRoot = new();

    public WarehouseState()
    {
        Logger = new Logger();
        _warehouses = SeedSampleData();
    }

    public Logger Logger { get; }

    public IReadOnlyList<Warehouse> Warehouses => _warehouses;

    public Warehouse? FindWarehouse(int id)
    {
        return _warehouses.FirstOrDefault(w => w.Id == id);
    }

    public Warehouse? DisposalWarehouse => _warehouses.FirstOrDefault(w => w.Type == WarehouseType.Disposal);

    public Product UpsertProduct(int id, int supplierId, string name, double unitVolume, decimal unitPrice, int shelfLifeDays)
    {
        lock (_syncRoot)
        {
            if (_products.TryGetValue(id, out var existing))
            {
                existing.UpdateData(supplierId, name, unitVolume, unitPrice, shelfLifeDays);
                return existing;
            }

            var product = new Product(id, supplierId, name, unitVolume, unitPrice, shelfLifeDays);
            _products[id] = product;
            return product;
        }
    }

    private List<Warehouse> SeedSampleData()
    {
        var generalWarehouse = new Warehouse(1, WarehouseType.General, 400, "Центральный склад, ул. Солнечная, 1");
        var coldWarehouse = new Warehouse(2, WarehouseType.Cold, 250, "Холодный склад, ул. Полярная, 7");
        var sortingWarehouse = new Warehouse(3, WarehouseType.Sorting, 200, "Сортировочный центр, ул. Логистическая, 3");
        var disposalWarehouse = new Warehouse(4, WarehouseType.Disposal, 300, "Склад утилизации, ул. Замыкающая, 10");

        var apples = RegisterProduct(new Product(100, 1, "Яблоки", 0.5, 2.5m, 25));
        var rice = RegisterProduct(new Product(101, 2, "Рис", 1.0, 10.0m, 120));
        var iceCream = RegisterProduct(new Product(102, 3, "Мороженое", 0.8, 5.0m, 15));
        var expiredJuice = RegisterProduct(new Product(103, 2, "Сок (просроченный)", 1.2, 3.0m, 0));

        generalWarehouse.AddProduct(rice, 50);
        generalWarehouse.AddProduct(apples, 10);
        generalWarehouse.AddProduct(expiredJuice, 5);
        coldWarehouse.AddProduct(iceCream, 60);
        sortingWarehouse.AddProduct(rice, 10);

        return new List<Warehouse> { generalWarehouse, coldWarehouse, sortingWarehouse, disposalWarehouse };
    }

    private Product RegisterProduct(Product product)
    {
        lock (_syncRoot)
        {
            _products[product.Id] = product;
        }

        return product;
    }
}
