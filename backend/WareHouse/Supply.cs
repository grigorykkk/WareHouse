using System;
using System.Collections.Generic;
using System.Linq;

namespace WarehouseSystem;

public class Supply
{
    private readonly List<ProductQuantity> _items;

    public Supply(IEnumerable<ProductQuantity> items)
    {
        if (items == null)
        {
            throw new ArgumentNullException(nameof(items));
        }

        _items = items.Select(i => new ProductQuantity(i.Product, i.Quantity)).ToList();
    }

    public IReadOnlyList<ProductQuantity> Items => _items.AsReadOnly();

    public void AddItem(Product product, int quantity)
    {
        _items.Add(new ProductQuantity(product, quantity));
    }

    public bool Process(IEnumerable<Warehouse> warehouses, Logger logger)
    {
        if (warehouses == null)
        {
            throw new ArgumentNullException(nameof(warehouses));
        }

        if (logger == null)
        {
            throw new ArgumentNullException(nameof(logger));
        }

        var warehouseList = warehouses.ToList();
        if (warehouseList.Count == 0)
        {
            throw new InvalidOperationException("Нет доступных складов для обработки поставки.");
        }

        var targetType = DetermineTargetWarehouseType();
        var targetWarehouses = warehouseList.Where(w => w.Type == targetType).OrderByDescending(w => w.FreeVolume).ToList();

        if (targetWarehouses.Count == 0)
        {
            throw new InvalidOperationException($"Склады типа {targetType} отсутствуют для размещения поставки.");
        }

        var fullyPlaced = true;

        foreach (var item in _items)
        {
            var remaining = item.Quantity;
            foreach (var warehouse in targetWarehouses)
            {
                if (remaining <= 0)
                {
                    break;
                }

                var capacityForItem = (int)Math.Floor(warehouse.FreeVolume / item.Product.UnitVolume);
                if (capacityForItem <= 0)
                {
                    continue;
                }

                var amountToPlace = Math.Min(remaining, capacityForItem);
                var added = warehouse.AddProduct(item.Product, amountToPlace);
                if (added)
                {
                    remaining -= amountToPlace;
                    logger.LogMovement(item.Product, amountToPlace, null, warehouse);
                }
            }

            if (remaining > 0)
            {
                fullyPlaced = false;
                logger.LogNote($"Не хватило места для товара {item.Product.Name}. Осталось {remaining} шт. неразмещёнными.");
            }
        }

        return fullyPlaced;
    }

    private WarehouseType DetermineTargetWarehouseType()
    {
        if (_items.Count == 0)
        {
            throw new InvalidOperationException("Поставка пуста.");
        }

        var allLongShelfLife = _items.All(item => item.Product.ShelfLifeDays >= 30);
        var allShortShelfLife = _items.All(item => item.Product.ShelfLifeDays < 30);

        if (allLongShelfLife)
        {
            return WarehouseType.General;
        }

        if (allShortShelfLife)
        {
            return WarehouseType.Cold;
        }

        return WarehouseType.Sorting;
    }
}
