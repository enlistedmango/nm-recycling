import React, { useState, useEffect } from "react";
import { debugData } from "@/utils/debugData";
import { fetchNui } from "@/utils/fetchNui";
import ScaleFade from "@/transitions/ScaleFade";
import { useNuiEvent } from "@/hooks/useNuiEvent";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import LibIcon from "@/components/LibIcon";
import { Progress } from "@/components/ui/progress";

// This will set the NUI to visible if we are developing in browser
debugData([
    {
        action: "showUi",
        data: true,
    },
]);

interface Material {
    label: string;
    icon: string;
    processingTime: number;
}

interface RecyclableItem {
    label: string;
    type: string;
    processingTime: number;
    icon: string;
    output?: Array<{
        item: string;
        amount: number;
    }>;
}

interface Batch {
    id: number;
    amount: number;
    item: string;
    item_type: string;
    completed: boolean;
    timeLeft: number;
    isOwner: boolean;
    target_material?: string;
}

interface RobberyConfig {
    enabled: boolean;
    minProcessedPercent: number;
    hackingTime: number;
    hackItem: string;
    successChance: number;
    cooldown: number;
    rewardPercent: number;
}

interface RecyclingData {
    materials: Record<string, Material>;
    recyclableItems: Record<string, RecyclableItem>;
    activeBatches: number;
    maxBatches: number;
    materialCount: number;
    itemCounts: Record<string, number>;
    locationId: number;
    robberyConfig: RobberyConfig;
}

const App: React.FC = () => {
    const [visible, setVisible] = useState(false);
    const [activeTab, setActiveTab] = useState("recycle");
    const [recyclingData, setRecyclingData] = useState<RecyclingData | null>(null);
    const [batches, setBatches] = useState<Batch[]>([]);
    const [selectedItem, setSelectedItem] = useState<string | null>(null);
    const [selectedTargetMaterial, setSelectedTargetMaterial] = useState<string | null>(null);
    const [selectedAmount, setSelectedAmount] = useState<number>(1);
    const [processingFee, setProcessingFee] = useState<number>(0);
    const [showConfirmation, setShowConfirmation] = useState(false);
    const [timerTick, setTimerTick] = useState(0);
    const [isRobbing, setIsRobbing] = useState(false);
    const [robbingBatchId, setRobbingBatchId] = useState<number | null>(null);

    useNuiEvent<any>("showUi", (data) => {
        console.log("Received showUi event with data:", data);
        setVisible(true);
        fetchRecyclingData(data && data.locationId ? data.locationId : 1);
    });

    useNuiEvent("hideUi", () => setVisible(false));

    const fetchRecyclingData = (locationId = 1) => {
        console.log("Fetching recycling data with locationId:", locationId);

        fetchNui<RecyclingData>("getRecyclingData", { locationId })
            .then((data) => {
                console.log("Got recycling data from client:", data);
                setRecyclingData(data);
            })
            .catch((e) => {
                console.error("Error fetching recycling data", e);
                // mock data for development purposes
                setRecyclingData({
                    materials: {
                        "plastic": { label: "Plastic", icon: "fas fa-prescription-bottle", processingTime: 2000 },
                        "steel": { label: "Steel", icon: "fas fa-layer-group", processingTime: 3000 },
                    },
                    recyclableItems: {
                        "recyclable_materials": {
                            label: "Recyclable Materials",
                            type: "choice",
                            processingTime: 2000,
                            icon: "fas fa-recycle"
                        },
                        "lockpick": {
                            label: "Lockpick",
                            type: "fixed",
                            processingTime: 3000,
                            icon: "fas fa-unlock",
                            output: [
                                { item: "metalscrap", amount: 2 },
                                { item: "steel", amount: 1 },
                                { item: "plastic", amount: 1 }
                            ]
                        }
                    },
                    activeBatches: 1,
                    maxBatches: 3,
                    materialCount: 150,
                    itemCounts: {
                        "recyclable_materials": 150,
                        "lockpick": 5,
                        "phone": 2,
                        "radio": 0
                    },
                    locationId: 1,
                    robberyConfig: {
                        enabled: false,
                        minProcessedPercent: 50,
                        hackingTime: 10000,
                        hackItem: "lockpick",
                        successChance: 50,
                        cooldown: 300000,
                        rewardPercent: 50
                    }
                });
            });
    };

    // Fetch batch data
    const fetchBatches = () => {
        if (!recyclingData) return;

        console.log(`Fetching batches with locationId: ${recyclingData.locationId} (${typeof recyclingData.locationId})`);

        fetchNui<Batch[]>("getBatches", {
            locationId: recyclingData.locationId
        })
            .then((data) => {
                console.log(`Got batches from client for location #${recyclingData.locationId}:`, data);
                setBatches(data);
            })
            .catch((e) => {
                console.error("Error fetching batches", e);
                // Set mock data for development
                setBatches([
                    {
                        id: 1,
                        amount: 50,
                        item: "recyclable_materials",
                        item_type: "choice",
                        completed: false,
                        timeLeft: 180,
                        isOwner: true,
                        target_material: "plastic"
                    },
                    {
                        id: 2,
                        amount: 25,
                        item: "lockpick",
                        item_type: "fixed",
                        completed: true,
                        timeLeft: 0,
                        isOwner: false
                    }
                ]);
            });
    };

    const startProcessing = () => {
        if (!selectedItem || !recyclingData) return;

        fetchNui("startBatchProcessing", {
            amount: selectedAmount,
            itemType: selectedItem,
            targetMaterial: selectedItem === "recyclable_materials" ? selectedTargetMaterial : undefined,
            processingFee: processingFee,
            locationId: recyclingData.locationId
        })
            .then(() => {
                fetchRecyclingData();
                setSelectedItem(null);
                setSelectedTargetMaterial(null);
                setSelectedAmount(1);
                setProcessingFee(0);
                setShowConfirmation(false);
            })
            .catch((e) => {
                console.error("Error starting batch processing", e);
            });
    };

    const collectBatch = (batchId: number) => {
        if (!recyclingData) return;

        fetchNui("collectBatch", {
            batchId: batchId,
            locationId: recyclingData.locationId
        })
            .then(() => {
                fetchBatches();
            })
            .catch((e) => {
                console.error("Error collecting batch", e);
            });
    };

    const calculateFee = (amount: number) => {
        if (!recyclingData) return 0;
        return 5 + (amount * 0.2);
    };

    const handleItemSelect = (itemId: string) => {
        setSelectedItem(itemId);
        setSelectedTargetMaterial(null);
        if (recyclingData) {
            setSelectedAmount(1);
            setProcessingFee(calculateFee(1));
        }
    };

    const handleTargetMaterialSelect = (materialId: string) => {
        setSelectedTargetMaterial(materialId);
    };

    const handleAmountChange = (amount: number) => {
        if (!recyclingData) return;

        const maxAmount = recyclingData.materialCount;
        let validAmount = Math.min(Math.max(1, amount), maxAmount);

        setSelectedAmount(validAmount);
        setProcessingFee(calculateFee(validAmount));
    };

    const handleConfirmation = () => {
        setShowConfirmation(true);
    };

    const handleRobBatch = (batchId: number) => {
        if (!recyclingData || isRobbing) return;

        setIsRobbing(true);
        setRobbingBatchId(batchId);

        fetchNui("canRobBatch", {
            batchId: batchId,
            locationId: recyclingData.locationId
        })
            .then((response) => {
                if (!response.success) {
                    setIsRobbing(false);
                    setRobbingBatchId(null);
                    return;
                }

                fetchNui("attemptRobBatch", {
                    batchId: batchId,
                    locationId: recyclingData.locationId
                })
                    .then((robResponse) => {
                        if (robResponse.success) {
                            fetchBatches();
                        }
                        setIsRobbing(false);
                        setRobbingBatchId(null);
                    })
                    .catch(() => {
                        setIsRobbing(false);
                        setRobbingBatchId(null);
                    });
            })
            .catch(() => {
                setIsRobbing(false);
                setRobbingBatchId(null);
            });
    };

    useEffect(() => {
        if (activeTab === "status" && visible) {
            fetchBatches();
        }
    }, [activeTab, visible]);

    useEffect(() => {
        const handleKeyDown = (event: KeyboardEvent) => {
            if (event.key === 'Escape' && visible) {
                handleClose();
            }
        };

        window.addEventListener('keydown', handleKeyDown);

        return () => {
            window.removeEventListener('keydown', handleKeyDown);
        };
    }, [visible]);

    useEffect(() => {
        if (!visible || activeTab !== "status" || batches.length === 0) return;

        const hasIncompleteBatches = batches.some(batch => !batch.completed);
        if (!hasIncompleteBatches) return;

        const timer = setInterval(() => {
            setBatches(prev =>
                prev.map(batch => {
                    if (batch.completed) return batch;

                    const newTimeLeft = Math.max(0, batch.timeLeft - 1);
                    const newCompleted = newTimeLeft === 0;

                    if (newCompleted && !batch.completed) {
                        setTimeout(() => fetchBatches(), 0);
                    }

                    return {
                        ...batch,
                        timeLeft: newTimeLeft,
                        completed: newCompleted
                    };
                })
            );
            setTimerTick(prev => prev + 1);
        }, 1000);

        return () => clearInterval(timer);
    }, [visible, activeTab, batches.length, timerTick]);

    useEffect(() => {
        if (!visible || activeTab !== "status") return;

        const refreshTimer = setInterval(() => {
            fetchBatches();
        }, 30000);

        return () => clearInterval(refreshTimer);
    }, [visible, activeTab]);

    const handleClose = () => {
        setVisible(false);
        setSelectedItem(null);
        setSelectedTargetMaterial(null);
        setSelectedAmount(1);
        setProcessingFee(0);
        setShowConfirmation(false);
        fetchNui("hideFrame");
    };

    const formatTimeRemaining = (seconds: number) => {
        const minutes = Math.floor(seconds / 60);
        const remainingSeconds = seconds % 60;
        return minutes > 0
            ? `${minutes} min ${remainingSeconds} sec`
            : `${remainingSeconds} seconds`;
    };

    return (
        <div className="fixed inset-0 flex items-center justify-center">
            <ScaleFade visible={visible}>
                <div className="w-full max-w-xl">
                    <Card className="border-border/40 bg-card/95 shadow-xl">
                        <CardHeader className="relative">
                            <div className="absolute right-4 top-4">
                                <Button variant="ghost" size="icon" onClick={handleClose} className="h-8 w-8 rounded-full">
                                    <LibIcon icon="xmark" className="h-4 w-4" />
                                </Button>
                            </div>
                            <div className="flex items-center space-x-2">
                                <Badge variant="outline" className="bg-primary/10 text-primary px-2 py-1">
                                    <LibIcon icon="recycle" className="mr-1 h-3 w-3" />
                                    Recycling
                                </Badge>
                                {recyclingData && (
                                    <Badge variant="secondary" className="px-2 py-1">
                                        Station #{recyclingData.locationId}
                                    </Badge>
                                )}
                            </div>
                            <CardTitle className="text-xl mt-2">Recycling Station</CardTitle>
                            <CardDescription>
                                Exchange your recyclable materials or items for useful resources.
                            </CardDescription>
                        </CardHeader>

                        <Tabs defaultValue="recycle" value={activeTab} onValueChange={setActiveTab} className="w-full">
                            <div className="px-6">
                                <TabsList className="w-full">
                                    <TabsTrigger value="recycle" className="flex-1">
                                        <LibIcon icon="recycle" className="mr-2 h-4 w-4" />
                                        Recycle Materials
                                    </TabsTrigger>
                                    <TabsTrigger value="status" className="flex-1">
                                        <LibIcon icon="hourglass-half" className="mr-2 h-4 w-4" />
                                        Processing Status
                                        {recyclingData && (
                                            <Badge variant="outline" className="ml-2 bg-primary/10 text-primary">
                                                {recyclingData.activeBatches}/{recyclingData.maxBatches}
                                            </Badge>
                                        )}
                                    </TabsTrigger>
                                </TabsList>
                            </div>

                            <CardContent className="pt-6">
                                <TabsContent value="recycle" className="mt-0">
                                    {recyclingData && recyclingData.activeBatches >= recyclingData.maxBatches ? (
                                        <div className="text-center p-4">
                                            <LibIcon icon="exclamation-circle" className="text-amber-500 text-4xl mb-2" />
                                            <p className="text-sm text-muted-foreground">
                                                You have reached the maximum of {recyclingData.maxBatches} active batches.
                                                Please collect or wait for your current batches to complete.
                                            </p>
                                        </div>
                                    ) : showConfirmation ? (
                                        <div className="space-y-4">
                                            <div className="bg-muted/50 p-4 rounded-md">
                                                <h3 className="font-medium mb-2">Confirm Exchange</h3>
                                                <div className="space-y-2 text-sm">
                                                    <div className="flex justify-between">
                                                        <span>Amount:</span>
                                                        <span className="font-medium">{selectedAmount} units</span>
                                                    </div>
                                                    <div className="flex justify-between">
                                                        <span>Item:</span>
                                                        <span className="font-medium">
                                                            {selectedItem && recyclingData?.recyclableItems[selectedItem]?.label}
                                                        </span>
                                                    </div>
                                                    {selectedItem === "recyclable_materials" && selectedTargetMaterial && (
                                                        <div className="flex justify-between">
                                                            <span>Target Material:</span>
                                                            <span className="font-medium">
                                                                {recyclingData?.materials[selectedTargetMaterial]?.label}
                                                            </span>
                                                        </div>
                                                    )}
                                                    <div className="flex justify-between">
                                                        <span>Processing Fee:</span>
                                                        <span className="font-medium">£{processingFee.toFixed(2)}</span>
                                                    </div>
                                                    <div className="flex justify-between">
                                                        <span>Estimated Time:</span>
                                                        <span className="font-medium">
                                                            ~{Math.ceil((selectedItem && recyclingData?.recyclableItems[selectedItem]?.processingTime || 0) / 1000 * selectedAmount / 60)} minutes
                                                        </span>
                                                    </div>
                                                </div>
                                            </div>

                                            <div className="flex space-x-2">
                                                <Button
                                                    variant="outline"
                                                    className="flex-1"
                                                    onClick={() => setShowConfirmation(false)}
                                                >
                                                    Cancel
                                                </Button>
                                                <Button
                                                    className="flex-1"
                                                    onClick={startProcessing}
                                                >
                                                    Confirm
                                                </Button>
                                            </div>
                                        </div>
                                    ) : selectedItem ? (
                                        <div className="space-y-4">
                                            <div className="flex items-center space-x-2">
                                                <Button
                                                    variant="ghost"
                                                    size="sm"
                                                    onClick={() => setSelectedItem(null)}
                                                >
                                                    <LibIcon icon="arrow-left" className="h-4 w-4 mr-1" />
                                                    Back
                                                </Button>
                                                <h3 className="font-medium">
                                                    {recyclingData?.recyclableItems[selectedItem]?.label || "Selected Item"}
                                                </h3>
                                            </div>

                                            <div className="space-y-4">
                                                <div>
                                                    <label className="text-sm font-medium">
                                                        Amount to Process (Max: {recyclingData?.itemCounts[selectedItem || ""] || 0})
                                                    </label>
                                                    <div className="flex items-center space-x-2 mt-1">
                                                        <Button
                                                            variant="outline"
                                                            size="icon"
                                                            onClick={() => handleAmountChange(selectedAmount - 1)}
                                                            disabled={selectedAmount <= 1}
                                                        >
                                                            <LibIcon icon="minus" className="h-4 w-4" />
                                                        </Button>
                                                        <Input
                                                            type="number"
                                                            value={selectedAmount}
                                                            onChange={(e) => handleAmountChange(parseInt(e.target.value))}
                                                            min={1}
                                                            max={recyclingData?.itemCounts[selectedItem || ""] || 0}
                                                            className="text-center"
                                                        />
                                                        <Button
                                                            variant="outline"
                                                            size="icon"
                                                            onClick={() => handleAmountChange(selectedAmount + 1)}
                                                            disabled={!!recyclingData && selectedAmount >= recyclingData.itemCounts[selectedItem || ""]}
                                                        >
                                                            <LibIcon icon="plus" className="h-4 w-4" />
                                                        </Button>
                                                    </div>
                                                </div>

                                                {selectedItem === "recyclable_materials" && (
                                                    <div>
                                                        <label className="text-sm font-medium">Target Material</label>
                                                        <div className="grid grid-cols-3 gap-2 mt-1">
                                                            {recyclingData && Object.entries(recyclingData.materials).map(([id, material]) => (
                                                                <Button
                                                                    key={id}
                                                                    variant={selectedTargetMaterial === id ? "default" : "outline"}
                                                                    className="h-auto py-2 justify-start"
                                                                    onClick={() => handleTargetMaterialSelect(id)}
                                                                >
                                                                    <LibIcon icon={material.icon as any} className="mr-2 h-4 w-4" />
                                                                    <span className="text-sm">{material.label}</span>
                                                                </Button>
                                                            ))}
                                                        </div>
                                                    </div>
                                                )}

                                                <div className="bg-muted/50 p-3 rounded-md">
                                                    <div className="flex justify-between text-sm">
                                                        <span>Processing Fee:</span>
                                                        <span>£{processingFee.toFixed(2)}</span>
                                                    </div>
                                                </div>

                                                <Button
                                                    className="w-full"
                                                    onClick={handleConfirmation}
                                                    disabled={selectedItem === "recyclable_materials" && !selectedTargetMaterial}
                                                >
                                                    Process Materials
                                                </Button>
                                            </div>
                                        </div>
                                    ) : (
                                        <div className="space-y-4">
                                            <div>
                                                <h3 className="font-medium mb-2">Recyclable Materials</h3>
                                                <ScrollArea className="h-64">
                                                    <div className="space-y-2">
                                                        {recyclingData && Object.entries(recyclingData.recyclableItems).map(([id, item]) => {
                                                            const itemCount = recyclingData.itemCounts[id] || 0;
                                                            const hasItem = itemCount > 0;

                                                            return (
                                                                <Button
                                                                    key={id}
                                                                    variant="outline"
                                                                    className="w-full justify-between h-auto py-3"
                                                                    onClick={() => handleItemSelect(id)}
                                                                    disabled={!hasItem}
                                                                >
                                                                    <div className="flex items-center">
                                                                        <LibIcon icon={item.icon as any} className="mr-2 h-4 w-4" />
                                                                        <span>{item.label}</span>
                                                                    </div>
                                                                    <div className="flex flex-col items-end text-xs text-muted-foreground">
                                                                        <span>
                                                                            {hasItem ? `Available: ${itemCount}` : "Not available"}
                                                                        </span>
                                                                        <span>Process Time: {Math.ceil(item.processingTime / 1000)}s</span>
                                                                        {item.type === "fixed" && (
                                                                            <span>Fixed Output</span>
                                                                        )}
                                                                    </div>
                                                                </Button>
                                                            );
                                                        })}
                                                    </div>
                                                </ScrollArea>
                                            </div>
                                        </div>
                                    )}
                                </TabsContent>

                                <TabsContent value="status" className="mt-0">
                                    <ScrollArea className="h-64">
                                        <div className="space-y-3">
                                            {recyclingData?.robberyConfig?.enabled && (
                                                <div className="bg-amber-500/10 p-3 rounded-md mb-2">
                                                    <div className="flex items-center text-amber-500 font-medium">
                                                        <LibIcon icon="exclamation-triangle" className="mr-2 h-4 w-4" />
                                                        <span>Robbery Information</span>
                                                    </div>
                                                    <p className="text-xs text-muted-foreground mt-1">
                                                        You can attempt to hack other players' batches.<br />
                                                        Required: {recyclingData.robberyConfig.hackItem}<br />
                                                        Reward: {recyclingData.robberyConfig.rewardPercent}% of materials
                                                    </p>
                                                </div>
                                            )}

                                            {batches.length > 0 ? batches.map((batch) => (
                                                <div key={batch.id} className="bg-muted/50 p-3 rounded-md">
                                                    <div className="flex justify-between items-start">
                                                        <div>
                                                            <h4 className="font-medium">
                                                                {batch.item_type === "recyclable_materials" && batch.target_material
                                                                    ? `Recyclable → ${recyclingData?.materials[batch.target_material]?.label}`
                                                                    : recyclingData?.recyclableItems[batch.item]?.label || batch.item}
                                                            </h4>
                                                            <div className="text-sm text-muted-foreground">
                                                                <div className="flex items-center">
                                                                    <LibIcon icon={batch.isOwner ? "lock" : "users"} className="mr-1 h-3 w-3" />
                                                                    <span>{batch.isOwner ? "Your Batch" : "Other Player's Batch"}</span>
                                                                </div>
                                                                <div>Amount: {batch.amount} units</div>
                                                            </div>
                                                        </div>
                                                        {batch.completed ? (
                                                            <Badge variant="outline" className="bg-green-500/10 text-green-500">
                                                                Completed
                                                            </Badge>
                                                        ) : (
                                                            <Badge variant="outline" className="bg-amber-500/10 text-amber-500">
                                                                Processing
                                                            </Badge>
                                                        )}
                                                    </div>

                                                    {!batch.completed && (
                                                        <div className="mt-2">
                                                            <div className="flex justify-between text-xs mb-1">
                                                                <span>Progress</span>
                                                                <span>{formatTimeRemaining(batch.timeLeft)} remaining</span>
                                                            </div>
                                                            <Progress
                                                                value={Math.max(0, Math.min(100, 100 - (batch.timeLeft / (batch.amount * 0.3) * 100)))}
                                                                className="h-2"
                                                            />
                                                        </div>
                                                    )}

                                                    {batch.isOwner && batch.completed ? (
                                                        <Button
                                                            className="w-full mt-2"
                                                            onClick={() => collectBatch(batch.id)}
                                                        >
                                                            Collect Batch
                                                        </Button>
                                                    ) : (!batch.isOwner && !batch.completed && recyclingData?.robberyConfig?.enabled && (
                                                        <Button
                                                            className="w-full mt-2"
                                                            variant="destructive"
                                                            onClick={() => handleRobBatch(batch.id)}
                                                            disabled={isRobbing || !recyclingData?.itemCounts[recyclingData.robberyConfig.hackItem]}
                                                        >
                                                            {isRobbing && robbingBatchId === batch.id ? (
                                                                <>
                                                                    <span className="animate-pulse">Hacking...</span>
                                                                </>
                                                            ) : (
                                                                <>
                                                                    <LibIcon icon="laptop-code" className="mr-2 h-4 w-4" />
                                                                    Attempt to Hack
                                                                </>
                                                            )}
                                                        </Button>
                                                    ))}
                                                </div>
                                            )) : (
                                                <div className="text-center p-4">
                                                    <LibIcon icon="info-circle" className="text-muted-foreground text-4xl mb-2" />
                                                    <p className="text-muted-foreground">No active batches found.</p>
                                                </div>
                                            )}
                                        </div>
                                    </ScrollArea>
                                </TabsContent>
                            </CardContent>
                        </Tabs>
                    </Card>
                </div>
            </ScaleFade>
        </div>
    );
};

export default App;
